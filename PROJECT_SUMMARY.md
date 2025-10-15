# Project Summary: airflow-dbt-duckdb

## What Was Built

A complete, production-ready data pipeline orchestration setup combining:
- **Apache Airflow 2.10.0** for workflow orchestration
- **dbt 1.8.0** for SQL-based transformations
- **DuckDB** as the analytical database
- **Astronomer Cosmos** for seamless dbt-Airflow integration
- **Docker Compose** for local development

## Repository Structure

```
airflow-dbt-duckdb/
├── dags/                       # Airflow DAG definitions
│   ├── dbt_analytics_dag.py   # Cosmos-based DAG (recommended)
│   └── simple_dbt_dag.py      # BashOperator alternative
│
├── dbt/                        # Complete dbt project
│   ├── models/
│   │   ├── staging/           # stg_customers, stg_orders (views)
│   │   └── marts/             # customer_orders (table)
│   ├── seeds/                 # Sample CSV data
│   ├── tests/                 # Data quality tests
│   ├── macros/                # Reusable SQL functions
│   ├── dbt_project.yml        # dbt configuration
│   ├── profiles.yml           # DuckDB connection
│   └── packages.yml           # dbt dependencies
│
├── docker/
│   └── Dockerfile             # Extended Airflow image
│
├── data/                       # Raw data files (optional)
├── include/                    # Additional SQL/templates
│
├── docker-compose.yml          # Service orchestration
├── requirements.txt            # Python dependencies
├── Makefile                    # Developer commands
├── .gitignore                  # Git ignore rules
├── .env.example               # Environment template
├── README.md                   # Full documentation
└── QUICKSTART.md              # 5-minute setup guide
```

## Key Features

### 1. Two DAG Approaches

**Cosmos-based (Recommended)**
- Automatic task generation from dbt models
- Full lineage visibility in Airflow UI
- Task-level retries and monitoring

**BashOperator-based (Alternative)**
- Direct dbt CLI commands
- Simpler, more transparent
- Good for learning

### 2. Complete dbt Project

**Staging Models** (Views)
- `stg_customers`: Cleaned customer data
- `stg_orders`: Cleaned order data

**Marts Models** (Tables)
- `customer_orders`: Aggregated customer analytics

**Data Quality Tests**
- Unique/not null constraints
- Referential integrity checks
- Documented in schema.yml

### 3. Developer Experience

**Makefile Commands**
```bash
make init          # One-time initialization
make up            # Start services
make down          # Stop services
make dbt-run       # Run dbt models
make dbt-test      # Run data tests
make duckdb-cli    # Query warehouse
make logs          # View logs
make clean         # Full cleanup
```

### 4. DuckDB Integration

- Warehouse stored at `/opt/warehouse/warehouse.duckdb`
- Shared Docker volume for persistence
- Supports concurrent reads
- Serialized writes (enforced by DAG)

## Getting Started

### Quick Start (5 minutes)

```bash
# 1. Initialize
make init

# 2. Start services
make up

# 3. Access Airflow UI
# http://localhost:8080
# Username: airflow | Password: airflow

# 4. Enable and run the dbt_analytics_pipeline DAG

# 5. Query results
make duckdb-cli
```

See QUICKSTART.md for detailed walkthrough.

### Development Workflow

1. **Add data**: Place CSVs in `dbt/seeds/`
2. **Create models**: Add SQL files in `dbt/models/`
3. **Document**: Update `schema.yml` files
4. **Test**: Add tests in schema.yml or `tests/`
5. **Run**: `make dbt-run && make dbt-test`
6. **Deploy**: Push to git, DAG updates automatically

## Technical Architecture

### Service Stack

```
┌─────────────────┐
│  Airflow UI     │ :8080
└────────┬────────┘
         │
┌────────▼────────┐
│ Airflow Webserver
└────────┬────────┘
         │
┌────────▼────────┐
│ Airflow Scheduler│
└────────┬────────┘
         │
┌────────▼────────┐
│   PostgreSQL    │ (Airflow metadata)
└─────────────────┘

         │
┌────────▼────────┐
│   dbt Core      │ (SQL transformations)
└────────┬────────┘
         │
┌────────▼────────┐
│    DuckDB       │ (Analytics warehouse)
└─────────────────┘
```

### Data Flow

```
CSV Seeds → dbt seed → DuckDB (seeds schema)
     ↓
Staging Models (views)
     ↓
Marts Models (tables)
     ↓
Tests & Validation
```

## Configuration Files

### Key Configurations

**`dbt_project.yml`**
- Project name: analytics
- Staging: views in staging schema
- Marts: tables in marts schema

**`profiles.yml`**
- Target: dev
- Type: duckdb
- Path: /opt/warehouse/warehouse.duckdb

**`docker-compose.yml`**
- Airflow 2.10.0
- LocalExecutor
- Shared warehouse volume
- Port 8080 for web UI

**`requirements.txt`**
- apache-airflow==2.10.0
- dbt-core==1.8.0
- dbt-duckdb==1.8.3
- astronomer-cosmos==1.7.1

## Sample Data

**Customers** (10 records)
- customer_id, customer_name, email, created_at

**Orders** (20 records)
- order_id, customer_id, order_date, order_amount

**Customer Orders Mart**
- Aggregates: total_orders, total_spent
- Date ranges: first_order_date, last_order_date

## Production Considerations

### Recommended Enhancements

1. **Executor**: Upgrade to CeleryExecutor or KubernetesExecutor
2. **Storage**: Use persistent SSD-backed volumes
3. **Backups**: Regular DuckDB file snapshots
4. **Monitoring**: Add Airflow alerts and SLAs
5. **Secrets**: Use Airflow Connections for credentials
6. **CI/CD**: Add GitHub Actions for dbt testing
7. **Documentation**: Auto-generate dbt docs

### Scaling Strategies

**For larger datasets:**
- Use incremental dbt models
- Partition DuckDB tables
- Implement CDC patterns
- Consider distributed storage

**For more pipelines:**
- Multiple dbt projects
- DAG factories for dynamic generation
- Shared macros and utilities

## Resources

### Documentation
- [Full README](README.md) - Complete setup guide
- [Quick Start](QUICKSTART.md) - 5-minute setup
- [Makefile](Makefile) - All commands with `make help`

### External Links
- [Airflow Docs](https://airflow.apache.org/docs/)
- [dbt Docs](https://docs.getdbt.com/)
- [DuckDB Docs](https://duckdb.org/docs/)
- [Cosmos Docs](https://astronomer.github.io/astronomer-cosmos/)

## License

MIT

---

**Built with**: Apache Airflow • dbt • DuckDB • Docker • Python
**Use case**: Modern data pipeline orchestration
**Deployment**: Local development, production-ready architecture
