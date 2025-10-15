# Quick Start Guide

Get up and running with the Airflow + dbt + DuckDB stack in 5 minutes!

## Step-by-Step Setup

### 1. Initialize the Environment

```bash
# Create .env file
make init
```

This will:
- Create necessary directories (logs, plugins, data)
- Set up environment variables
- Initialize the Airflow database
- Create default admin user

### 2. Start Services

```bash
make up
```

Wait about 30-60 seconds for services to start. You should see:
```
Services started! Access Airflow at http://localhost:8080
Username: airflow | Password: airflow
```

### 3. Access Airflow UI

Open your browser and navigate to: http://localhost:8080

Login credentials:
- **Username**: `airflow`
- **Password**: `airflow`

### 4. Run Your First Pipeline

1. In the Airflow UI, find the `dbt_analytics_pipeline` DAG
2. Toggle the switch on the left to enable it (it starts paused)
3. Click the play button (▶) on the right to trigger a manual run
4. Watch the task progress in the Graph or Grid view

### 5. Explore the Results

Query the DuckDB warehouse:

```bash
make duckdb-cli
```

Then run SQL queries:

```sql
-- See all tables
SHOW TABLES;

-- Query the marts
SELECT * FROM marts.customer_orders LIMIT 10;

-- Analyze customer spending
SELECT
    customer_name,
    total_orders,
    total_spent,
    ROUND(total_spent / total_orders, 2) as avg_order_value
FROM marts.customer_orders
WHERE total_orders > 0
ORDER BY total_spent DESC;
```

Exit DuckDB CLI with `.quit`

## Common Commands

```bash
make help              # Show all available commands
make logs              # View service logs
make dbt-run           # Run dbt models manually
make dbt-test          # Run dbt tests
make down              # Stop services
make restart           # Restart services
make clean             # Clean up everything
```

## Understanding the Pipeline

The `dbt_analytics_pipeline` DAG performs these steps:

1. **dbt seed**: Loads CSV files from `dbt/seeds/` into DuckDB
   - `raw_customers.csv` → `seeds.raw_customers` table
   - `raw_orders.csv` → `seeds.raw_orders` table

2. **dbt run (staging)**: Creates staging views
   - `stg_customers`: Cleaned customer data
   - `stg_orders`: Cleaned order data

3. **dbt run (marts)**: Creates analytics tables
   - `customer_orders`: Customer analytics with aggregated metrics

4. **dbt test**: Validates data quality
   - Unique/not null constraints
   - Referential integrity
   - Custom business rules

## Project Structure Overview

```
airflow-dbt-duckdb/
├── dags/              # Airflow DAG definitions
├── dbt/               # dbt project (models, seeds, tests)
├── docker/            # Docker configuration
├── data/              # Raw data files (optional)
├── Makefile           # Common commands
└── README.md          # Full documentation
```

## Next Steps

1. **Add Your Own Data**
   - Place CSV files in `dbt/seeds/`
   - Run `make dbt-seed`

2. **Create New Models**
   - Add `.sql` files in `dbt/models/staging/` or `dbt/models/marts/`
   - Document in `schema.yml`
   - Run `make dbt-run`

3. **Customize the DAG**
   - Edit `dags/dbt_analytics_dag.py`
   - Change schedule, add tasks, configure alerts

4. **Explore dbt Features**
   - Macros (reusable SQL)
   - Tests (data quality)
   - Documentation (`make dbt-docs-generate`)

## Troubleshooting

**Services won't start?**
```bash
make logs  # Check for errors
```

**DAG not appearing?**
- Wait 30 seconds for Airflow to scan DAG files
- Check logs: `make logs-scheduler`

**DuckDB locked error?**
- Only one write operation at a time is allowed
- Tasks are serialized by default in the DAG

**Need to reset everything?**
```bash
make clean  # Remove all containers and volumes
make init   # Start fresh
make up
```

## Learn More

- Full documentation: [README.md](README.md)
- dbt models: `dbt/models/`
- DAG definitions: `dags/`
- Makefile commands: `make help`

Happy data engineering!
