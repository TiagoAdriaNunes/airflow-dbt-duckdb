"""
Initialize TPC-H benchmark data into a DuckLake catalog backed by PostgreSQL.
Generates ~1 GB of synthetic supply-chain data (scale factor = 1).
Idempotent: skips generation if tables already exist in lakehouse.raw.

PostgreSQL is used as the DuckLake catalog (supports multiple concurrent clients).
Parquet data files are stored at DUCKLAKE_DATA_PATH inside the warehouse volume.
"""

import os
import duckdb
import psycopg2

CATALOG_CONN = os.environ.get(
    "DUCKLAKE_CATALOG_CONN",
    "postgres:dbname=ducklake_catalog host=postgres user=airflow password=airflow",
)
DATA_PATH = os.environ.get("DUCKLAKE_DATA_PATH", "/opt/warehouse/data")
SCALE_FACTOR = 1  # sf=1 ≈ 1 GB (150k customers, 1.5M orders, 6M lineitems)

TABLES = ["customer", "orders", "lineitem", "supplier", "nation", "region", "part", "partsupp"]


def ensure_catalog_db() -> None:
    """Create the ducklake_catalog PostgreSQL database if it doesn't exist."""
    # Parse host/user/password from the connection string for the admin connection
    params = dict(p.split("=", 1) for p in CATALOG_CONN.split() if "=" in p)
    try:
        admin = psycopg2.connect(
            host=params.get("host", "postgres"),
            user=params.get("user", "airflow"),
            password=params.get("password", "airflow"),
            dbname="postgres",  # connect to default db to run CREATE DATABASE
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


def init_tpch(catalog_conn: str = CATALOG_CONN, data_path: str = DATA_PATH) -> None:
    ensure_catalog_db()

    conn = duckdb.connect()  # in-memory — dbgen writes here, then we copy to DuckLake
    conn.execute("INSTALL ducklake; LOAD ducklake")
    conn.execute("INSTALL postgres; LOAD postgres")
    # DATA_PATH is persisted in catalog metadata — only needed on first ATTACH
    conn.execute(f"ATTACH 'ducklake:{catalog_conn}' AS lakehouse (DATA_PATH '{data_path}')")

    try:
        row_count = conn.execute("SELECT count(*) FROM lakehouse.raw.customer").fetchone()[0]
        print(f"TPC-H already present in DuckLake ({row_count:,} customers). Skipping.")
        conn.close()
        return
    except duckdb.CatalogException:
        pass  # fresh catalog — proceed with generation

    conn.execute("CREATE SCHEMA IF NOT EXISTS lakehouse.raw")

    print(f"Generating TPC-H data (scale factor={SCALE_FACTOR}, ~1 GB)...")
    conn.execute("INSTALL tpch; LOAD tpch")
    conn.execute(f"CALL dbgen(sf={SCALE_FACTOR})")

    print("Copying TPC-H tables into DuckLake (lakehouse.raw)...")
    for table in TABLES:
        conn.execute(f"CREATE TABLE lakehouse.raw.{table} AS SELECT * FROM {table}")

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

    conn.close()
    print("Done.")


if __name__ == "__main__":
    init_tpch()
