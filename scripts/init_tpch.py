"""
Initialize TPC-H benchmark data in the DuckDB warehouse.
Generates ~1 GB of synthetic supply-chain data (scale factor = 1).
Idempotent: skips generation if tables already exist.
"""

import os
import duckdb

WAREHOUSE_PATH = os.environ.get("DUCKDB_WAREHOUSE_PATH", "/opt/warehouse/warehouse.duckdb")
SCALE_FACTOR = 1  # sf=1 ≈ 1 GB (150k customers, 1.5M orders, 6M lineitems)


def init_tpch(warehouse_path: str = WAREHOUSE_PATH) -> None:
    conn = duckdb.connect(warehouse_path)

    existing = conn.execute(
        "SELECT count(*) FROM information_schema.tables "
        "WHERE table_schema = 'main' AND table_name = 'customer'"
    ).fetchone()[0]

    if existing:
        row_count = conn.execute("SELECT count(*) FROM main.customer").fetchone()[0]
        print(f"TPC-H already present ({row_count:,} customers). Skipping.")
        conn.close()
        return

    print(f"Generating TPC-H data (scale factor={SCALE_FACTOR}, ~1 GB)...")
    conn.execute("INSTALL tpch")
    conn.execute("LOAD tpch")
    conn.execute(f"CALL dbgen(sf={SCALE_FACTOR})")

    counts = conn.execute("""
        SELECT 'customer' AS tbl, count(*) AS rows FROM customer
        UNION ALL SELECT 'orders',  count(*) FROM orders
        UNION ALL SELECT 'lineitem', count(*) FROM lineitem
        UNION ALL SELECT 'supplier', count(*) FROM supplier
        UNION ALL SELECT 'nation',   count(*) FROM nation
        UNION ALL SELECT 'region',   count(*) FROM region
    """).fetchall()

    print("TPC-H tables created:")
    for table, count in counts:
        print(f"  {table:<12} {count:>10,} rows")

    conn.close()
    print("Done.")


if __name__ == "__main__":
    init_tpch()
