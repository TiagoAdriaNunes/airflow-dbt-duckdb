# airflow-dbt-duckdb

A lightweight, fully containerised analytics stack: Apache Airflow orchestrates a TPC-H benchmark pipeline that loads raw data into **DuckLake**, then runs dbt transformations to produce analytics-ready tables — all running locally via Docker Compose.

## Tech Stack

| Tool | Version | Role |
|------|---------|------|
| Apache Airflow | 2.10 | Pipeline orchestration |
| dbt | 1.9 | SQL transformations |
| DuckDB + DuckLake | 1.3 | Analytical engine + open table format |
| Astronomer Cosmos | latest | dbt ↔ Airflow integration |
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
       Generates TPC-H sf=1 (~1 GB) via dbgen,
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
│   ├── seeds/                  # CSV seed data (raw_customers, raw_orders)
│   ├── dbt_project.yml
│   ├── profiles.yml            # DuckDB/DuckLake connection (local / dev / prod)
│   └── packages.yml
├── scripts/
│   ├── init_tpch.py            # Generates TPC-H data into lakehouse.raw
│   └── query_duckdb.py         # CLI query tool for the lakehouse catalog
├── docker/
│   └── Dockerfile
├── docker-compose.yml
├── Makefile
└── .env.example
```

---

## Quick Start

### Prerequisites

- Docker and Docker Compose
- 6 GB free disk (TPC-H sf=1 ≈ 1 GB raw, plus Airflow overhead)
- 4 GB available RAM

### Setup

```bash
git clone https://github.com/yourusername/airflow-dbt-duckdb.git
cd airflow-dbt-duckdb

cp .env.example .env
make init   # one-time Airflow DB init
make up     # start webserver + scheduler
```

Open **http://localhost:8080** (user: `airflow`, password: `airflow`).

### Running the Pipeline

1. Enable the `dbt_analytics_pipeline` DAG in the UI
2. Click **Trigger DAG**
3. `init_tpch` runs first (~2 min to generate 1 GB of TPC-H data), then dbt models run

Or trigger dbt manually without Airflow:

```bash
make dbt-run    # run all 5 models against lakehouse
make dbt-test   # run data quality tests
```

---

## Makefile Reference

### Services

```bash
make init            # One-time Airflow initialisation
make up              # Start webserver + scheduler
make down            # Stop all services
make restart         # down + up
make logs            # Tail all container logs
make logs-scheduler  # Tail scheduler logs only
make clean           # Remove containers, volumes, and generated files
make rebuild         # Rebuild Docker image and restart
```

### dbt

```bash
make dbt-run          # Run all models (writes to lakehouse.marts + lakehouse.staging)
make dbt-test         # Run all data quality tests
make dbt-seed         # Load CSV seeds into dbt.duckdb
make dbt-build        # deps + seed + run + test in one shot
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

---

## Development

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DUCKLAKE_CATALOG_CONN` | `postgres:dbname=ducklake_catalog host=postgres user=airflow password=airflow` | DuckLake PostgreSQL catalog connection string |
| `DUCKLAKE_DATA_PATH` | `/opt/warehouse/data` | Directory for Parquet data files (used only on first `ATTACH`) |

These are set in `docker-compose.yml` and consumed by `init_tpch.py`, `query_duckdb.py`, and `dbt/profiles.yml`.

---

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

### Resetting the Lakehouse

To wipe DuckLake data and start fresh (e.g., to re-run `init_tpch`):

```bash
make down
docker volume rm airflow-dbt-duckdb_warehouse airflow-dbt-duckdb_postgres-db-volume
make init && make up
# Trigger the DAG — init_tpch will recreate ducklake_catalog and regenerate all data
```

---

## Troubleshooting

### `make dbt-run` fails with "schema does not exist"
The `generate_schema_name` macro (`dbt/macros/`) ensures models land in `lakehouse.marts` and `lakehouse.staging` — not `marts_marts`/`marts_staging`. If you see this after a fresh clone, run `make dbt-run` once to create the schemas.

### `make dbt-run` fails with "Cascade Drop not supported in DuckLake"
The `drop_relation` macro (`dbt/macros/`) handles this. If you're seeing it, check that the macro file is present and that Docker has the latest volume-mounted `dbt/` directory.

### Airflow won't start
```bash
make logs          # check for startup errors
make clean         # wipe volumes
make init && make up
```

---

## Production Notes

- **DuckLake concurrency**: the PostgreSQL catalog supports multiple concurrent clients. dbt models run in parallel (4 threads on `dev`, 8 on `prod`). Each Cosmos task gets its own in-memory DuckDB connection (`:memory:`) and attaches the shared PostgreSQL catalog.
- **Scaling data volume**: change `SCALE_FACTOR` in `scripts/init_tpch.py` (sf=10 ≈ 10 GB). Wipe the warehouse volume and the postgres volume first so `init_tpch` re-runs.
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
