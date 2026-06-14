#!/usr/bin/env python3
"""
Simple DuckDB query script for exploring data stored in DuckLake.
Usage: python query_duckdb.py [query_type]
"""
import os
import sys
import duckdb

CATALOG_CONN = os.environ.get(
    "DUCKLAKE_CATALOG_CONN",
    "postgres:dbname=ducklake_catalog host=postgres user=airflow password=airflow",
)


def get_conn():
    conn = duckdb.connect()
    conn.execute("INSTALL ducklake; LOAD ducklake")
    conn.execute("INSTALL postgres; LOAD postgres")
    conn.execute(f"ATTACH 'ducklake:{CATALOG_CONN}' AS lakehouse")
    return conn


def run_query(sql, description="Query Result"):
    try:
        conn = get_conn()
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
    sql = """
        SELECT schema_name AS table_schema, table_name, column_count AS columns
        FROM duckdb_tables()
        WHERE database_name = 'lakehouse'
        ORDER BY schema_name, table_name
    """
    run_query(sql, "All Tables in DuckLake")


def show_customer_orders():
    sql = """
        SELECT customer_name, market_segment, total_orders,
               printf('$%.2f', total_spent) as total_spent,
               open_orders, fulfilled_orders,
               first_order_date, last_order_date
        FROM lakehouse.marts.customer_orders
        ORDER BY total_spent DESC
        LIMIT 20
    """
    run_query(sql, "Top 20 Customers by Spend")


def show_statistics():
    sql = """
        SELECT
            COUNT(*) as total_customers,
            SUM(total_orders) as total_orders,
            printf('$%.2f', SUM(total_spent)) as total_revenue,
            printf('$%.2f', AVG(total_spent)) as avg_customer_value,
            printf('$%.2f', MIN(total_spent)) as min_customer_value,
            printf('$%.2f', MAX(total_spent)) as max_customer_value
        FROM lakehouse.marts.customer_orders
    """
    run_query(sql, "Order Statistics")


def show_recent_orders():
    sql = """
        SELECT r.order_id, c.customer_name, c.market_segment,
               r.order_priority,
               printf('$%.2f', r.list_price)    as list_price,
               printf('$%.2f', r.net_revenue)   as net_revenue,
               r.line_count, r.returned_lines,
               r.order_date
        FROM lakehouse.marts.order_revenue r
        JOIN lakehouse.staging.stg_customers c ON r.customer_id = c.customer_id
        ORDER BY r.order_date DESC
        LIMIT 10
    """
    run_query(sql, "Recent Orders")


def show_revenue_by_segment():
    sql = """
        SELECT c.market_segment,
               COUNT(*)                              as total_orders,
               printf('$%.2f', SUM(r.net_revenue))  as net_revenue,
               printf('$%.2f', AVG(r.net_revenue))  as avg_order_revenue,
               ROUND(AVG(r.return_rate_pct), 2)     as avg_return_rate_pct
        FROM lakehouse.marts.order_revenue r
        JOIN lakehouse.staging.stg_customers c ON r.customer_id = c.customer_id
        GROUP BY c.market_segment
        ORDER BY SUM(r.net_revenue) DESC
    """
    run_query(sql, "Revenue by Market Segment")


def main():
    if len(sys.argv) < 2:
        print("Usage: python query_duckdb.py [tables|orders|stats|recent|revenue|sql '<query>']")
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
    elif query_type == 'revenue':
        show_revenue_by_segment()
    elif query_type == 'sql' and len(sys.argv) > 2:
        run_query(sys.argv[2], "Custom Query Result")
    else:
        print(f"Unknown query type: {query_type}")
        sys.exit(1)


if __name__ == '__main__':
    main()
