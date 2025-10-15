# DuckDB Data Exploration Guide

This guide provides multiple ways to explore your DuckDB data.

## Quick Start

After the setup is complete, you can explore your data using these commands:

### 1. Show All Tables
```bash
make duckdb-show-tables
```

### 2. View Customer Orders
```bash
make duckdb-customer-orders
```

### 3. Show Order Statistics
```bash
make duckdb-stats
```

### 4. Show Recent Orders
```bash
make duckdb-recent
```

### 5. Interactive Menu Explorer
```bash
make duckdb-explore
# Or run directly:
./explore_data.sh
```

### 6. DuckDB CLI (After Rebuild)
```bash
make duckdb-cli
```
This will open an interactive DuckDB CLI where you can run any SQL query.

### 7. Custom SQL Query
```bash
make duckdb-query SQL="SELECT * FROM main_marts.customer_orders WHERE total_orders > 2"
```

## Setup Required

To enable the DuckDB CLI, you need to rebuild the Docker image once:

```bash
# Stop containers
docker compose down

# Rebuild with DuckDB CLI included
docker compose build

# Start containers
docker compose up -d

# Wait for services to be ready (about 60 seconds)
sleep 60

# Test it out
make duckdb-cli
```

## Available Make Commands

Run `make help` to see all available commands:

```
make help                    # Show all commands
make duckdb-cli              # Open DuckDB CLI (interactive SQL)
make duckdb-show-tables      # List all tables
make duckdb-customer-orders  # Show customer orders
make duckdb-stats            # Show statistics
make duckdb-recent           # Show recent orders
make duckdb-explore          # Interactive menu
make duckdb-query SQL="..."  # Run custom query
```

## Data Structure

Your DuckDB database contains the following tables:

### Seeds (Raw Data)
- `main_seeds.raw_customers` - Raw customer data (10 rows)
- `main_seeds.raw_orders` - Raw order data (20 rows)

### Staging Layer
- `main_staging.stg_customers` - Cleaned customer data
- `main_staging.stg_orders` - Cleaned order data

### Marts Layer
- `main_marts.customer_orders` - Aggregated customer metrics
  - Columns: customer_id, customer_name, email, total_orders, total_spent, first_order_date, last_order_date

## Example Queries

Once in the DuckDB CLI or using `make duckdb-query SQL="..."`:

```sql
-- Show all tables
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema LIKE 'main%';

-- Top 5 customers by spending
SELECT customer_name, total_orders, total_spent
FROM main_marts.customer_orders
ORDER BY total_spent DESC
LIMIT 5;

-- Recent orders with customer names
SELECT o.order_id, c.customer_name, o.order_amount, o.order_date
FROM main_staging.stg_orders o
JOIN main_staging.stg_customers c ON o.customer_id = c.customer_id
ORDER BY o.order_date DESC
LIMIT 10;

-- Customer count by order frequency
SELECT
  CASE
    WHEN total_orders = 1 THEN '1 order'
    WHEN total_orders BETWEEN 2 AND 3 THEN '2-3 orders'
    ELSE '4+ orders'
  END as order_frequency,
  COUNT(*) as customer_count
FROM main_marts.customer_orders
GROUP BY order_frequency;
```

## DuckDB CLI Commands

Inside the DuckDB CLI, you can use these special commands:

```sql
.tables              -- List all tables
.schema table_name   -- Show table schema
.mode                -- Change output format
.help                -- Show all commands
.quit                -- Exit CLI
```

## Troubleshooting

### DuckDB CLI not found
If you get "duckdb: command not found", you need to rebuild the image:
```bash
docker compose down
docker compose build
docker compose up -d
```

### Python module not found
If you get "ModuleNotFoundError: No module named 'duckdb'", wait for pip packages to install:
```bash
# Check logs
docker compose logs airflow-scheduler | grep -i "Successfully installed"

# Restart to ensure packages are loaded
docker compose restart
```

### Scripts not found
If you get "can't open file '/opt/airflow/scripts/query_duckdb.py'":
```bash
# Make sure scripts directory exists
ls -la scripts/

# Restart containers to mount the volume
docker compose down
docker compose up -d
```

## Alternative: Direct Docker Exec

If make commands don't work, you can run queries directly:

```bash
# Show tables
docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py tables

# Show customer orders
docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py orders

# Custom query
docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("SELECT * FROM main_marts.customer_orders LIMIT 5").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
```

## Database Location

The DuckDB database file is located at:
- **Inside container:** `/opt/warehouse/warehouse.duckdb`
- **Docker volume:** `airflow-dbt-duckdb_warehouse`

To copy the database to your local machine:
```bash
docker compose cp airflow-scheduler:/opt/warehouse/warehouse.duckdb ./data/warehouse.duckdb
```

## Related Files

- `explore_data.sh` - Interactive data exploration script
- `scripts/query_duckdb.py` - Python script for querying DuckDB
- `Makefile` - Contains all make commands
- `docker/Dockerfile` - Custom image with DuckDB CLI
- `docker-compose.yml` - Service configuration

## Need Help?

```bash
make help              # See all available commands
./verify_setup.sh      # Verify your setup
make logs-scheduler    # Check scheduler logs
make logs-airflow      # Check webserver logs
```
