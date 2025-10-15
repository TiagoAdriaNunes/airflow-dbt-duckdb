#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  DuckDB Data Explorer${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Check if query was provided as argument
if [ $# -eq 1 ]; then
    echo -e "${YELLOW}Running query:${NC} $1"
    echo ""
    docker compose exec -T airflow-scheduler python << EOF
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""$1""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
else
    echo -e "${GREEN}Available queries:${NC}"
    echo ""
    echo -e "  ${YELLOW}1.${NC} All tables"
    echo -e "  ${YELLOW}2.${NC} Customer orders (all)"
    echo -e "  ${YELLOW}3.${NC} Top 5 spenders"
    echo -e "  ${YELLOW}4.${NC} Recent orders"
    echo -e "  ${YELLOW}5.${NC} Order statistics"
    echo -e "  ${YELLOW}6.${NC} Raw customers"
    echo -e "  ${YELLOW}7.${NC} Raw orders"
    echo -e "  ${YELLOW}8.${NC} Custom query"
    echo ""
    echo -n "Select option (1-8): "
    read option

    case $option in
        1)
            echo -e "\n${BLUE}📊 All Tables:${NC}"
            docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""
    SELECT table_schema, table_name,
           (SELECT COUNT(*) FROM information_schema.columns c WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name) as columns
    FROM information_schema.tables t
    WHERE table_schema LIKE 'main%'
    ORDER BY table_schema, table_name
""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
            ;;
        2)
            echo -e "\n${BLUE}💰 Customer Orders (All):${NC}"
            docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""
    SELECT customer_name, total_orders, printf('$%.2f', total_spent) as total_spent,
           first_order_date, last_order_date
    FROM main_marts.customer_orders
    ORDER BY total_spent DESC
""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
            ;;
        3)
            echo -e "\n${BLUE}🏆 Top 5 Spenders:${NC}"
            docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""
    SELECT customer_name, total_orders, printf('$%.2f', total_spent) as total_spent,
           first_order_date, last_order_date
    FROM main_marts.customer_orders
    ORDER BY total_spent DESC LIMIT 5
""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
            ;;
        4)
            echo -e "\n${BLUE}📅 Recent Orders:${NC}"
            docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""
    SELECT o.order_id, c.customer_name,
           printf('$%.2f', o.order_amount) as amount, o.order_date
    FROM main_staging.stg_orders o
    JOIN main_staging.stg_customers c ON o.customer_id = c.customer_id
    ORDER BY o.order_date DESC LIMIT 10
""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
            ;;
        5)
            echo -e "\n${BLUE}📈 Order Statistics:${NC}"
            docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""
    SELECT
        COUNT(*) as total_customers,
        SUM(total_orders) as total_orders,
        printf('$%.2f', SUM(total_spent)) as total_revenue,
        printf('$%.2f', AVG(total_spent)) as avg_customer_value,
        printf('$%.2f', MIN(total_spent)) as min_customer_value,
        printf('$%.2f', MAX(total_spent)) as max_customer_value
    FROM main_marts.customer_orders
""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
            ;;
        6)
            echo -e "\n${BLUE}👥 Raw Customers:${NC}"
            docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""
    SELECT * FROM main_seeds.raw_customers
""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
            ;;
        7)
            echo -e "\n${BLUE}🛒 Raw Orders:${NC}"
            docker compose exec -T airflow-scheduler python << 'EOF'
import duckdb
conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
result = conn.execute("""
    SELECT order_id, customer_id, printf('$%.2f', order_amount) as amount, order_date
    FROM main_seeds.raw_orders ORDER BY order_date DESC
""").fetchdf()
print(result.to_string(index=False))
conn.close()
EOF
            ;;
        8)
            echo -e "\n${YELLOW}Enter your SQL query:${NC}"
            echo -e "${YELLOW}(Example: SELECT * FROM main_marts.customer_orders WHERE total_orders > 2)${NC}"
            echo -n "> "
            read custom_query
            echo ""
            docker compose exec -T airflow-scheduler python << EOF
import duckdb
try:
    conn = duckdb.connect('/opt/warehouse/warehouse.duckdb', read_only=True)
    result = conn.execute("""$custom_query""").fetchdf()
    print(result.to_string(index=False))
    conn.close()
except Exception as e:
    print(f"Error: {e}")
EOF
            ;;
        *)
            echo -e "${YELLOW}Invalid option${NC}"
            exit 1
            ;;
    esac
fi

echo ""
echo -e "${GREEN}Done!${NC}"
