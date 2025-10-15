# airflow-dbt-duckdb

Modern data pipeline orchestration using Apache Airflow, dbt, and DuckDB. This project demonstrates how to build a lightweight, portable analytics stack that runs entirely in containers.

## Overview

This repository provides a complete setup for running dbt transformations on DuckDB, orchestrated by Apache Airflow using Astronomer Cosmos.

### Tech Stack

- **Apache Airflow 2.10.0**: Workflow orchestration
- **dbt 1.8.0**: SQL-based data transformations
- **DuckDB**: In-process analytical database
- **Astronomer Cosmos**: dbt + Airflow integration
- **Docker Compose**: Local development environment

## Repository Structure

```
airflow-dbt-duckdb/
├── dags/                       # Airflow DAG definitions
│   ├── dbt_analytics_dag.py   # Cosmos-based dbt DAG
│   └── simple_dbt_dag.py      # BashOperator-based alternative
├── dbt/                        # dbt project
│   ├── models/
│   │   ├── staging/           # Staging models (views)
│   │   └── marts/             # Analytics models (tables)
│   ├── seeds/                 # CSV seed files
│   ├── tests/                 # Custom data tests
│   ├── macros/                # SQL macros
│   ├── dbt_project.yml        # dbt project configuration
│   ├── profiles.yml           # DuckDB connection profile
│   └── packages.yml           # dbt package dependencies
├── docker/                     # Docker configuration
│   └── Dockerfile             # Extended Airflow image
├── data/                       # Raw data files
├── include/                    # Additional SQL/templates
├── docker-compose.yml          # Docker services definition
├── requirements.txt            # Python dependencies
├── Makefile                    # Common commands
├── .env.example               # Environment variable template
└── README.md                   # This file
```

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- At least 4GB of available RAM
- Git

### Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/airflow-dbt-duckdb.git
cd airflow-dbt-duckdb
```

2. Create environment file:
```bash
cp .env.example .env
```

3. Initialize Airflow:
```bash
make init
```

4. Start the services:
```bash
make up
```

5. Access the Airflow UI:
   - URL: http://localhost:8080
   - Username: `airflow`
   - Password: `airflow`

### Running the Pipeline

Once Airflow is running:

1. Navigate to http://localhost:8080
2. Enable the `dbt_analytics_pipeline` DAG
3. Trigger a manual run using the play button

The DAG will:
- Run dbt seed to load sample data
- Execute staging models (views)
- Build marts models (tables)
- Run all dbt tests

## Project Components

### dbt Models

#### Staging Layer (`dbt/models/staging/`)
- `stg_customers.sql`: Clean customer data from seeds
- `stg_orders.sql`: Clean order data from seeds

#### Marts Layer (`dbt/models/marts/`)
- `customer_orders.sql`: Aggregated customer analytics with order metrics

### Airflow DAGs

#### `dbt_analytics_dag.py` (Recommended)
Uses Astronomer Cosmos to automatically generate Airflow tasks from dbt models. Provides:
- Automatic task dependency resolution
- Task-level retries and monitoring
- Full lineage visibility in Airflow UI

#### `simple_dbt_dag.py` (Alternative)
Uses BashOperator to run dbt commands directly. Useful for:
- Understanding dbt CLI commands
- Simple pipelines without Cosmos dependency
- Custom dbt command sequences

### DuckDB Configuration

The DuckDB warehouse file is stored at `/opt/warehouse/warehouse.duckdb` in a shared Docker volume. This ensures:
- Data persistence across container restarts
- Shared access between Airflow tasks
- Easy backup and portability

**Important**: DuckDB supports concurrent reads but serialize write operations to avoid locking issues.

## Development

### Adding New dbt Models

1. Create a new `.sql` file in `dbt/models/staging/` or `dbt/models/marts/`
2. Add model documentation in the corresponding `schema.yml`
3. Test locally with dbt CLI:
```bash
make dbt-run
```

### Testing dbt Models

Run all tests:
```bash
make dbt-test
```

Run specific model tests:
```bash
docker exec -it airflow-dbt-duckdb-airflow-webserver-1 \
  bash -c "cd /opt/airflow/dbt && dbt test --select stg_customers"
```

### Accessing the DuckDB Database

Query the warehouse directly:
```bash
make duckdb-cli
```

Or from within the container:
```bash
docker exec -it airflow-dbt-duckdb-airflow-webserver-1 \
  duckdb /opt/warehouse/warehouse.duckdb
```

## Makefile Commands

```bash
make init          # Initialize Airflow (first time only)
make up            # Start all services
make down          # Stop all services
make restart       # Restart all services
make logs          # View logs
make dbt-run       # Run dbt models
make dbt-test      # Run dbt tests
make dbt-debug     # Debug dbt connection
make duckdb-cli    # Open DuckDB CLI
make clean         # Clean up volumes and containers
```

## Configuration

### Airflow Settings

Key environment variables in `docker-compose.yml`:
- `AIRFLOW__CORE__EXECUTOR`: Set to `LocalExecutor`
- `AIRFLOW__CORE__LOAD_EXAMPLES`: Set to `false`
- `DUCKDB_WAREHOUSE_PATH`: Path to DuckDB file

### dbt Profile

The dbt profile (`dbt/profiles.yml`) configures DuckDB connection:
```yaml
analytics:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: '/opt/warehouse/warehouse.duckdb'
      threads: 4
```

## Troubleshooting

### Airflow won't start
```bash
# Check logs
make logs

# Rebuild containers
make clean
make init
make up
```

### dbt connection issues
```bash
# Test dbt connection
make dbt-debug

# Check DuckDB file permissions
docker exec -it airflow-dbt-duckdb-airflow-webserver-1 \
  ls -la /opt/warehouse/
```

### DuckDB locked errors
DuckDB supports concurrent reads but only one write at a time. Ensure your DAG serializes write operations.

## Production Considerations

1. **DuckDB Storage**: For production, consider:
   - Using persistent volume backed by SSD
   - Regular backups of the `.duckdb` file
   - Monitoring file size growth

2. **Airflow Executor**: Switch to CeleryExecutor or KubernetesExecutor for:
   - Parallel task execution
   - Better resource utilization
   - Horizontal scaling

3. **dbt Materialization**: Review materialization strategies:
   - `view`: Fast, no storage, query-time computation
   - `table`: Slower build, faster queries, storage required
   - `incremental`: For large datasets with append patterns

4. **Secrets Management**: Use Airflow Connections and Variables instead of hardcoded credentials

## Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [dbt Documentation](https://docs.getdbt.com/)
- [DuckDB Documentation](https://duckdb.org/docs/)
- [Astronomer Cosmos](https://astronomer.github.io/astronomer-cosmos/)
- [dbt-duckdb Adapter](https://github.com/duckdb/dbt-duckdb)

## License

MIT

## Contributing

Contributions welcome! Please open an issue or submit a pull request.
