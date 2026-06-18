# airflow-dbt-duckdb

A lightweight, fully containerised analytics stack: Apache Airflow orchestrates a TPC-H benchmark pipeline that loads raw data into **DuckLake**, runs dbt transformations to produce analytics-ready tables, and exposes pipeline and lakehouse metrics through a full observability stack — all running locally via Docker Compose.

## Tech Stack

| Tool | Version | Role |
|------|---------|------|
| Apache Airflow | 2.10 | Pipeline orchestration |
| dbt | 1.9 | SQL transformations |
| DuckDB + DuckLake | 1.3 | Analytical engine + open table format |
| Astronomer Cosmos | latest | dbt ↔ Airflow integration |
| Grafana | 13.0.2 | Metrics dashboards |
| Prometheus | v3.12.0 | Metrics storage |
| OpenTelemetry Collector | 0.154.0 | Metrics pipeline |
| Docker Compose | — | Local environment |

---

## How It Works

### Storage: PostgreSQL catalog + Parquet data

```
PostgreSQL (airflow DB container)
└── ducklake_catalog        ← DuckLake metadata: schema, transaction log, file registry

/opt/warehouse/data/        (shared Docker volume)
└── *.parquet               ← Parquet data files (actual table rows)
```

**DuckLake** is an open table format that separates metadata from data. The PostgreSQL database (`ducklake_catalog`) tracks schema and transactions; all row data lives as Parquet files on disk. Using PostgreSQL as the catalog (instead of a `.duckdb` file) allows multiple concurrent clients — enabling parallel dbt model execution across Cosmos tasks.

Any DuckDB process attaches the lakehouse with:

```sql
LOAD ducklake; LOAD postgres;
ATTACH 'ducklake:postgres:dbname=ducklake_catalog host=postgres user=airflow password=airflow'
    AS lakehouse;
```

This gives a `lakehouse` catalog with three schemas:

| Schema | Contents | Materialization |
|--------|----------|-----------------|
| `lakehouse.raw` | TPC-H source tables (customer, orders, lineitem, …) | DuckLake tables |
| `lakehouse.staging` | Cleaned/typed views over raw | dbt views |
| `lakehouse.marts` | Analytics aggregates | dbt tables |

---

### Pipeline: Airflow DAG

The `dbt_analytics_pipeline` DAG runs `@daily`:

```
start → init_tpch → dbt_run (Cosmos task group) → end
              │              │
              │    stg_customers ──┐
              │    stg_orders    ──┼─→ customer_orders
              │    stg_lineitem ──┘    order_revenue
              │
       Generates TPC-H data via dbgen (scale factor controlled by TPCH_SCALE_FACTOR),
       writes 8 tables into lakehouse.raw.
       Idempotent — skips if data already exists.
```

Cosmos automatically creates one Airflow task per dbt model, giving you task-level retries and lineage in the Airflow UI.

---

### dbt Models

**Staging** (`dbt/models/staging/`) — views, no storage cost:
- `stg_customers` — typed customer records from `raw.customer`
- `stg_orders` — cleaned order records from `raw.orders`
- `stg_lineitem` — line-item detail from `raw.lineitem`

**Marts** (`dbt/models/marts/`) — materialised tables:
- `customer_orders` — per-customer aggregates: total orders, spend, open vs. fulfilled counts, first/last order date
- `order_revenue` — per-order revenue: list price, net revenue after returns, return rate

---

### Observability Stack

```
ducklake-metrics ──OTLP──▶ otel-collector:4318 ──▶ Prometheus:9090 ──▶ Grafana:3000
                                                                              │
                                                         Airflow PostgreSQL ──┘
```

- **ducklake-metrics** — scrapes DuckLake catalog (snapshots, tables, files, size) every 60s and exports via OTLP
- **otel-collector** — receives OTLP metrics, exposes a Prometheus scrape endpoint on `:8889`
- **Prometheus** — scrapes otel-collector and stores time-series data
- **Grafana** — dashboards for both Airflow pipeline metrics (from PostgreSQL) and DuckLake catalog metrics (from Prometheus)

---

## Repository Structure

```
airflow-dbt-duckdb/
├── dags/
│   ├── dbt_analytics_dag.py    # Main DAG: init_tpch → Cosmos dbt task group
│   └── simple_dbt_dag.py       # Alternative: BashOperator-based dbt run
├── dbt/
│   ├── models/
│   │   ├── staging/            # Views over lakehouse.raw
│   │   └── marts/              # Analytics tables in lakehouse.marts
│   ├── macros/
│   │   ├── generate_schema_name.sql  # Use custom schema names as-is (no prefix)
│   │   └── drop_relation.sql         # DuckLake-safe DROP (no CASCADE)
│   ├── dbt_project.yml
│   ├── profiles.yml            # DuckDB/DuckLake connection (local / dev / prod)
│   └── packages.yml
├── scripts/
│   ├── init_tpch.py            # Generates TPC-H data into lakehouse.raw
│   └── query_duckdb.py         # CLI query tool for the lakehouse catalog
├── grafana/
│   ├── dashboards/             # Provisioned Grafana dashboards
│   └── provisioning/           # Datasource and dashboard provider config
├── otel/
│   └── otel-collector-config.yaml
├── prometheus/
│   └── prometheus.yml
├── docker/
│   ├── Dockerfile              # Airflow image (dbt, DuckDB, Cosmos)
│   ├── Dockerfile.metrics      # ducklake-metrics image
│   └── requirements.txt
├── docker-compose.yml
├── Makefile
├── .env.example
└── README.md
```

---

## Quick Start

### Prerequisites

- Docker Desktop (Mac/Windows) or Docker Engine (Linux)
- 8 GB free disk (TPC-H sf=1 ≈ 1 GB raw, plus Airflow + observability overhead)
- 4 GB available RAM

### First-time setup (one command)

```bash
git clone https://github.com/yourusername/airflow-dbt-duckdb.git
cd airflow-dbt-duckdb

make bootstrap
```

`bootstrap` does everything in sequence: initialises Airflow, builds the ducklake-metrics image, starts all services, waits for Airflow to be healthy, then triggers the pipeline.

Open **http://localhost:8080** (user: `airflow`, password: `airflow`).  
Open **http://localhost:3000** (user: `admin`, password: `admin`) for Grafana.

### Subsequent starts

```bash
make up           # start all services (images already built)
make pipeline-run # trigger the DAG manually if needed
```

---

## Makefile Reference

### Core

```bash
make bootstrap       # First-time setup: init + build + start + trigger pipeline
make init            # One-time Airflow initialisation (creates .env from .env.example)
make up              # Start all services
make down            # Stop all services
make restart         # down + up
make rebuild         # Rebuild Airflow image (cached) and restart
make rebuild-clean   # Force full rebuild with no cache
make ps              # Show running containers
make logs            # Tail all container logs
make logs-airflow    # Tail Airflow webserver logs
make logs-scheduler  # Tail Airflow scheduler logs
make clean           # Remove containers, volumes, and generated files
make deep-clean      # Nuclear: remove containers, volumes, built images, and build cache
```

### Pipeline

```bash
make pipeline-run    # Trigger the dbt_analytics_pipeline DAG
```

### dbt

```bash
make dbt-run          # Run all models (writes to lakehouse.marts + lakehouse.staging)
make dbt-test         # Run all data quality tests
make dbt-build        # deps + run + test in one shot
make dbt-debug        # Test dbt connection
make dbt-deps         # Install dbt packages
make dbt-docs-generate  # Generate dbt documentation site
make dbt-docs-serve     # Serve docs at http://localhost:8081
```

### Querying the Lakehouse

```bash
make lh-tables    # List all schemas and tables in the lakehouse
make lh-stats     # Order statistics (count, revenue, avg customer value)
make lh-orders    # Top 20 customers by spend
make lh-recent    # 10 most recent orders
make lh-revenue   # Net revenue by market segment

# Run any SQL directly
make lh-query SQL="SELECT * FROM lakehouse.marts.customer_orders LIMIT 5"

# Interactive DuckDB shell attached to the lakehouse catalog
make lh-cli
```

### Observability

```bash
make obs-build      # Build the ducklake-metrics image
make obs-up         # Start only the observability stack
make obs-down       # Stop only the observability services
make obs-logs       # Tail logs from all observability services
make obs-status     # Show container health + list DuckLake metrics in Prometheus
make logs-grafana   # Tail Grafana logs
make logs-prometheus  # Tail Prometheus logs
make logs-otel      # Tail OpenTelemetry Collector logs
make logs-metrics   # Tail ducklake-metrics exporter logs
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AIRFLOW_UID` | `50000` | UID for Airflow containers (50000 = Docker Desktop default) |
| `AIRFLOW_PROJ_DIR` | `.` | Project root mounted into Airflow containers |
| `TPCH_SCALE_FACTOR` | `1` | TPC-H data volume: sf=1 ≈ 1 GB, sf=3 ≈ 3 GB, sf=10 ≈ 10 GB |
| `DUCKLAKE_CATALOG_CONN` | `postgres:dbname=ducklake_catalog ...` | DuckLake PostgreSQL catalog connection string |
| `DUCKLAKE_DATA_PATH` | `/opt/warehouse/data` | Directory for Parquet data files |

Set overrides in `.env` (copied from `.env.example` by `make init`).

---

## Development

### Adding a New dbt Model

1. Create `dbt/models/marts/my_model.sql`
2. Add documentation and tests in `dbt/models/marts/schema.yml`
3. Run and test:

```bash
make dbt-run
make dbt-test
```

### Running a Specific dbt Model

```bash
docker compose exec airflow-scheduler bash -c \
  "cd /opt/airflow/dbt && DBT_PROFILES_DIR=/opt/airflow/dbt DBT_TARGET=dev \
   /opt/dbt-venv/bin/dbt run --select customer_orders"
```

### Adding Python Dependencies

Add the package to `docker/requirements.txt`, then rebuild:

```bash
make rebuild
```

Runtime `pip install` into a running container won't survive a restart — always bake deps into the image.

### Changing the TPC-H Data Volume

Edit `.env`:

```
TPCH_SCALE_FACTOR=3   # 3 GB
```

Then reset and reload:

```bash
make deep-clean
make bootstrap
```

`deep-clean` is required because `init_tpch` is idempotent — it skips generation if tables already exist.

### Resetting the Lakehouse

```bash
make deep-clean       # wipes all containers, volumes, and the built image
make bootstrap        # fresh start: init + build + start + trigger pipeline
```

---

## Troubleshooting

### `make dbt-run` fails with "schema does not exist"
The `generate_schema_name` macro (`dbt/macros/`) ensures models land in `lakehouse.marts` and `lakehouse.staging` — not `marts_marts`/`marts_staging`. If you see this after a fresh clone, run `make dbt-run` once to create the schemas.

### `make dbt-run` fails with "Cascade Drop not supported in DuckLake"
The `drop_relation` macro (`dbt/macros/`) handles this. If you're seeing it, check that the macro file is present and that Docker has the latest volume-mounted `dbt/` directory.

### `ducklake-metrics` reports "relation ducklake_snapshot does not exist"
The DuckLake catalog hasn't been initialised yet. Run `make pipeline-run` and wait for the DAG to complete (~5-10 min).

### Airflow won't start
```bash
make logs-scheduler   # check for startup errors
make deep-clean
make bootstrap
```

### Grafana dashboard shows no data
Check that the pipeline has run at least once (`make pipeline-run`). The "Airflow Pipeline Observability" dashboard queries the Airflow PostgreSQL database — data only appears after DAG runs exist.

---

## Production Notes

- **DuckLake concurrency**: the PostgreSQL catalog supports multiple concurrent clients. dbt models run in parallel (4 threads on `dev`, 8 on `prod`). Each Cosmos task gets its own in-memory DuckDB connection (`:memory:`) and attaches the shared PostgreSQL catalog.
- **Scaling data volume**: set `TPCH_SCALE_FACTOR` in `.env` (sf=10 ≈ 10 GB), then `make deep-clean && make bootstrap`.
- **Airflow executor**: LocalExecutor is used here. Parallel dbt models already run within each Airflow task via dbt threads. For full Airflow-level parallelism across DAG tasks, switch to CeleryExecutor or KubernetesExecutor.
- **Backups**: back up the `ducklake_catalog` PostgreSQL database and the `/opt/warehouse/data/` Parquet files together — they are not independent.

---

## Resources

- [DuckLake documentation](https://ducklake.select/)
- [dbt-duckdb adapter](https://github.com/duckdb/dbt-duckdb)
- [Astronomer Cosmos](https://astronomer.github.io/astronomer-cosmos/)
- [Apache Airflow documentation](https://airflow.apache.org/docs/)
- [TPC-H benchmark](https://www.tpc.org/tpch/)

## License

MIT
