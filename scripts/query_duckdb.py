#!/usr/bin/env python3
"""
Simple DuckDB query script for exploring data
Usage: python query_duckdb.py [query_type]
"""
import sys
import duckdb

DB_PATH = '/opt/warehouse/warehouse.duckdb'

def run_query(sql, description="Query Result"):
    """Execute a SQL query and print results"""
    try:
        conn = duckdb.connect(DB_PATH, read_only=True)
        result = conn.execute(sql).fetchdf()
        print(f"\n{description}:")
        print("=" * 70)
        print(result.to_string(index=False))
        print("=" * 70)
        conn.close()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

def show_tables():
    """Show all tables in the database"""
    sql = """
        SELECT table_schema, table_name,
               (SELECT COUNT(*) FROM information_schema.columns c
                WHERE c.table_schema = t.table_schema
                AND c.table_name = t.table_name) as columns
        FROM information_schema.tables t
        WHERE table_schema LIKE 'main%'
        ORDER BY table_schema, table_name
    """
    run_query(sql, "📊 All Tables")

def show_customer_orders():
    """Show customer orders"""
    sql = """
        SELECT customer_name, total_orders,
               printf('$%.2f', total_spent) as total_spent,
               first_order_date, last_order_date
        FROM main_marts.customer_orders
        ORDER BY total_spent DESC
    """
    run_query(sql, "💰 Customer Orders")

def show_statistics():
    """Show order statistics"""
    sql = """
        SELECT
            COUNT(*) as total_customers,
            SUM(total_orders) as total_orders,
            printf('$%.2f', SUM(total_spent)) as total_revenue,
            printf('$%.2f', AVG(total_spent)) as avg_customer_value,
            printf('$%.2f', MIN(total_spent)) as min_customer_value,
            printf('$%.2f', MAX(total_spent)) as max_customer_value
        FROM main_marts.customer_orders
    """
    run_query(sql, "📈 Order Statistics")

def show_recent_orders():
    """Show recent orders"""
    sql = """
        SELECT o.order_id, c.customer_name,
               printf('$%.2f', o.order_amount) as amount,
               o.order_date
        FROM main_staging.stg_orders o
        JOIN main_staging.stg_customers c ON o.customer_id = c.customer_id
        ORDER BY o.order_date DESC
        LIMIT 10
    """
    run_query(sql, "📅 Recent Orders")

def main():
    if len(sys.argv) < 2:
        print("Usage: python query_duckdb.py [tables|orders|stats|recent|sql '<query>']")
        sys.exit(1)

    query_type = sys.argv[1].lower()

    if query_type == 'tables':
        show_tables()
    elif query_type == 'orders':
        show_customer_orders()
    elif query_type == 'stats':
        show_statistics()
    elif query_type == 'recent':
        show_recent_orders()
    elif query_type == 'sql' and len(sys.argv) > 2:
        custom_sql = sys.argv[2]
        run_query(custom_sql, "Custom Query Result")
    else:
        print(f"Unknown query type: {query_type}")
        sys.exit(1)

if __name__ == '__main__':
    main()
