#!/usr/bin/env python3
"""
DuckLake OTLP metrics exporter.

Reads the DuckLake catalog (PostgreSQL ducklake_catalog DB) on each scrape
interval and emits OpenTelemetry gauge metrics to the configured OTLP endpoint.

Metrics emitted:
  ducklake_snapshots            - total snapshot count
  ducklake_snapshots_per_hour   - commits in the last hour
  ducklake_snapshot_age_seconds - seconds since the most recent snapshot
  ducklake_tables               - active (non-dropped) tables
  ducklake_schemas              - active schemas
  ducklake_data_files           - active Parquet data files
  ducklake_storage_bytes        - total bytes across active data files
  ducklake_records              - total records across active data files
  ducklake_files_pending_deletion
  ducklake_table_records        - records per table {schema, table}
  ducklake_table_storage_bytes  - bytes per table {schema, table}
  ducklake_table_data_files     - files per table {schema, table}
"""
import os
import time
import logging
import threading
import psycopg2
import psycopg2.extras

from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

PG_HOST     = os.environ.get("DUCKLAKE_PG_HOST", "localhost")
PG_PORT     = int(os.environ.get("DUCKLAKE_PG_PORT", "5432"))
PG_DB       = os.environ.get("DUCKLAKE_PG_DB", "ducklake_catalog")
PG_USER     = os.environ.get("DUCKLAKE_PG_USER", "airflow")
PG_PASSWORD = os.environ.get("DUCKLAKE_PG_PASSWORD", "airflow")
SCRAPE_INTERVAL = int(os.environ.get("SCRAPE_INTERVAL", "60"))
# OTEL_EXPORTER_OTLP_ENDPOINT is read by the SDK from env automatically

resource = Resource.create({"service.name": "ducklake-catalog", "service.version": "1.0.0"})
exporter = OTLPMetricExporter()
reader   = PeriodicExportingMetricReader(exporter, export_interval_millis=SCRAPE_INTERVAL * 1000)
provider = MeterProvider(resource=resource, metric_readers=[reader])
metrics.set_meter_provider(provider)
meter = metrics.get_meter("ducklake")

_cache: dict = {}
_lock = threading.Lock()


def _pg_conn():
    return psycopg2.connect(
        host=PG_HOST, port=PG_PORT, dbname=PG_DB,
        user=PG_USER, password=PG_PASSWORD, connect_timeout=10,
    )


def collect() -> None:
    try:
        conn = _pg_conn()
        cur  = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

        cur.execute("SELECT COUNT(*) FROM ducklake_snapshot")
        snapshots_total = cur.fetchone()[0]

        cur.execute(
            "SELECT COUNT(*) FROM ducklake_snapshot "
            "WHERE snapshot_time >= NOW() - INTERVAL '1 hour'"
        )
        snapshots_per_hour = cur.fetchone()[0]

        cur.execute(
            "SELECT EXTRACT(EPOCH FROM (NOW() - MAX(snapshot_time))) FROM ducklake_snapshot"
        )
        row = cur.fetchone()
        snapshot_age = float(row[0]) if row[0] is not None else 0.0

        cur.execute("SELECT COUNT(*) FROM ducklake_table WHERE end_snapshot IS NULL")
        tables = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM ducklake_schema WHERE end_snapshot IS NULL")
        schemas = cur.fetchone()[0]

        cur.execute(
            "SELECT COUNT(*), COALESCE(SUM(file_size_bytes), 0), COALESCE(SUM(record_count), 0) "
            "FROM ducklake_data_file WHERE end_snapshot IS NULL"
        )
        row = cur.fetchone()
        data_files, storage_bytes, records = int(row[0]), int(row[1]), int(row[2])

        cur.execute("SELECT COUNT(*) FROM ducklake_files_scheduled_for_deletion")
        pending_deletion = cur.fetchone()[0]

        cur.execute("""
            SELECT s.schema_name, t.table_name,
                   COUNT(df.data_file_id)              AS file_count,
                   COALESCE(SUM(df.file_size_bytes), 0) AS total_bytes,
                   COALESCE(SUM(df.record_count), 0)   AS total_records
            FROM ducklake_table t
            JOIN ducklake_schema s ON t.schema_id = s.schema_id
            LEFT JOIN ducklake_data_file df
                   ON df.table_id = t.table_id AND df.end_snapshot IS NULL
            WHERE t.end_snapshot IS NULL AND s.end_snapshot IS NULL
            GROUP BY s.schema_name, t.table_name
        """)
        per_table = [dict(r) for r in cur.fetchall()]

        cur.close()
        conn.close()

        with _lock:
            _cache.update({
                "snapshots":           snapshots_total,
                "snapshots_per_hour":  snapshots_per_hour,
                "snapshot_age":        snapshot_age,
                "tables":              tables,
                "schemas":             schemas,
                "data_files":          data_files,
                "storage_bytes":       storage_bytes,
                "records":             records,
                "pending_deletion":    pending_deletion,
                "per_table":           per_table,
            })

        log.info(
            "collected: %d snapshots | %d tables | %d files | %.1f MB",
            snapshots_total, tables, data_files, storage_bytes / 1_048_576,
        )
    except Exception as exc:
        log.error("collection failed: %s", exc)


# --- Observable gauge callbacks (called by the OTel reader at export time) ---

def _obs(key):
    def cb(_opts):
        with _lock:
            yield metrics.Observation(_cache.get(key, 0))
    return cb


def _obs_per_table(key):
    def cb(_opts):
        with _lock:
            for row in _cache.get("per_table", []):
                yield metrics.Observation(
                    row[key],
                    {"schema": row["schema_name"], "table": row["table_name"]},
                )
    return cb


meter.create_observable_gauge(
    "ducklake_snapshots", callbacks=[_obs("snapshots")],
    description="Total DuckLake snapshots (commits)")
meter.create_observable_gauge(
    "ducklake_snapshots_per_hour", callbacks=[_obs("snapshots_per_hour")],
    description="DuckLake commits in the last hour")
meter.create_observable_gauge(
    "ducklake_snapshot_age_seconds", callbacks=[_obs("snapshot_age")],
    description="Seconds since the most recent DuckLake snapshot", unit="s")
meter.create_observable_gauge(
    "ducklake_tables", callbacks=[_obs("tables")],
    description="Active (non-dropped) tables in DuckLake")
meter.create_observable_gauge(
    "ducklake_schemas", callbacks=[_obs("schemas")],
    description="Active schemas in DuckLake")
meter.create_observable_gauge(
    "ducklake_data_files", callbacks=[_obs("data_files")],
    description="Active Parquet data files in DuckLake")
meter.create_observable_gauge(
    "ducklake_storage_bytes", callbacks=[_obs("storage_bytes")],
    description="Total bytes across active DuckLake data files", unit="By")
meter.create_observable_gauge(
    "ducklake_records", callbacks=[_obs("records")],
    description="Total records across active DuckLake data files")
meter.create_observable_gauge(
    "ducklake_files_pending_deletion", callbacks=[_obs("pending_deletion")],
    description="DuckLake data files scheduled for deletion")
meter.create_observable_gauge(
    "ducklake_table_records", callbacks=[_obs_per_table("total_records")],
    description="Records per DuckLake table")
meter.create_observable_gauge(
    "ducklake_table_storage_bytes", callbacks=[_obs_per_table("total_bytes")],
    description="Storage bytes per DuckLake table", unit="By")
meter.create_observable_gauge(
    "ducklake_table_data_files", callbacks=[_obs_per_table("file_count")],
    description="Data files per DuckLake table")


def _collect_loop() -> None:
    while True:
        time.sleep(SCRAPE_INTERVAL)
        collect()


if __name__ == "__main__":
    log.info(
        "DuckLake metrics exporter starting (interval=%ds, pg=%s/%s)",
        SCRAPE_INTERVAL, PG_HOST, PG_DB,
    )
    collect()  # populate cache before first export
    threading.Thread(target=_collect_loop, daemon=True).start()
    while True:
        time.sleep(3600)
