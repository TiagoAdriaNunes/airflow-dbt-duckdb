"""
Initialize TPC-H benchmark data directly into DuckLake.
Generates ~1 GB of synthetic supply-chain data (scale factor = 1).
Idempotent: skips generation if tables already exist in lakehouse.raw.
"""

import os
import duckdb
import psycopg2

CATALOG_CONN = os.environ.get(
    "DUCKLAKE_CATALOG_CONN",
    "postgres:dbname=ducklake_catalog host=postgres user=airflow password=airflow",
)
DATA_PATH = os.environ.get("DUCKLAKE_DATA_PATH", "/opt/warehouse/data")
SCALE_FACTOR = float(os.environ.get("TPCH_SCALE_FACTOR", "1"))  # sf=1 ≈ 1 GB, sf=3 ≈ 3 GB
STAGING_DB = "/tmp/tpch_staging.duckdb"

TABLES = ["customer", "orders", "lineitem", "supplier", "nation", "region", "part", "partsupp"]


def ensure_catalog_db() -> None:
    params = dict(p.split("=", 1) for p in CATALOG_CONN.split() if "=" in p)
    try:
        admin = psycopg2.connect(
            host=params.get("host", "postgres"),
            user=params.get("user", "airflow"),
            password=params.get("password", "airflow"),
            dbname="postgres",
        )
        admin.autocommit = True
        cur = admin.cursor()
        cur.execute("SELECT 1 FROM pg_database WHERE datname = 'ducklake_catalog'")
        if not cur.fetchone():
            cur.execute("CREATE DATABASE ducklake_catalog")
            print("Created PostgreSQL database 'ducklake_catalog'.")
        admin.close()
    except Exception as e:
        print(f"Warning: could not ensure ducklake_catalog database: {e}")


def get_conn():
    conn = duckdb.connect()
    conn.execute("INSTALL ducklake; LOAD ducklake")
    conn.execute("INSTALL postgres; LOAD postgres")
    conn.execute(f"ATTACH 'ducklake:{CATALOG_CONN}' AS lakehouse (DATA_PATH '{DATA_PATH}')")
    return conn


def init_tpch() -> None:
    ensure_catalog_db()
    conn = get_conn()

    try:
        row_count = conn.execute("SELECT count(*) FROM lakehouse.raw.customer").fetchone()[0]
        print(f"TPC-H already present in DuckLake ({row_count:,} customers). Skipping.")
        conn.close()
        return
    except (duckdb.CatalogException, duckdb.InvalidInputException):
        conn.close()

    # Generate TPC-H into a disk-backed staging file to avoid holding ~1 GB in memory.
    size_hint = f"~{SCALE_FACTOR} GB" if SCALE_FACTOR >= 1 else f"~{int(SCALE_FACTOR * 1000)} MB"
    print(f"Generating TPC-H data (scale factor={SCALE_FACTOR}, {size_hint})...")
    staging = duckdb.connect(STAGING_DB)
    staging.execute("SET temp_directory='/tmp'")
    staging.execute("INSTALL tpch; LOAD tpch")
    staging.execute(f"CALL dbgen(sf={SCALE_FACTOR})")
    staging.close()  # tables flushed to STAGING_DB on disk

    print("Copying TPC-H tables into DuckLake (lakehouse.raw)...")
    conn = get_conn()
    try:
        conn.execute(f"ATTACH '{STAGING_DB}' AS staging (READ_ONLY)")
        conn.execute("CREATE SCHEMA IF NOT EXISTS lakehouse.raw")
        for table in TABLES:
            conn.execute(f"CREATE TABLE lakehouse.raw.{table} AS SELECT * FROM staging.{table}")

        counts = conn.execute("""
            SELECT 'customer'  AS tbl, count(*) AS rows FROM lakehouse.raw.customer
            UNION ALL SELECT 'orders',   count(*) FROM lakehouse.raw.orders
            UNION ALL SELECT 'lineitem', count(*) FROM lakehouse.raw.lineitem
            UNION ALL SELECT 'supplier', count(*) FROM lakehouse.raw.supplier
            UNION ALL SELECT 'nation',   count(*) FROM lakehouse.raw.nation
            UNION ALL SELECT 'region',   count(*) FROM lakehouse.raw.region
        """).fetchall()

        print("DuckLake tables created (lakehouse.raw):")
        for table, count in counts:
            print(f"  {table:<12} {count:>10,} rows")
    finally:
        conn.close()
        if os.path.exists(STAGING_DB):
            os.remove(STAGING_DB)

    print("Done.")


if __name__ == "__main__":
    init_tpch()
