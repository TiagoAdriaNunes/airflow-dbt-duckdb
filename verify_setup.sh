#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Airflow + dbt + DuckDB Setup Check${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Check if Docker is installed
echo -n "Checking Docker... "
if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓ Installed${NC}"
else
    echo -e "${RED}✗ Not installed${NC}"
    echo -e "${YELLOW}Please install Docker: https://docs.docker.com/get-docker/${NC}"
    exit 1
fi

# Check if Docker Compose is installed
echo -n "Checking Docker Compose... "
if command -v docker compose &> /dev/null || command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}✓ Installed${NC}"
else
    echo -e "${RED}✗ Not installed${NC}"
    echo -e "${YELLOW}Please install Docker Compose${NC}"
    exit 1
fi

# Check if Docker daemon is running
echo -n "Checking Docker daemon... "
if docker info &> /dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo -e "${YELLOW}Please start Docker${NC}"
    exit 1
fi

# Check directory structure
echo ""
echo "Checking directory structure..."

directories=("dags" "dbt" "dbt/models" "dbt/seeds" "docker" "data" "include")
for dir in "${directories[@]}"; do
    echo -n "  $dir... "
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
done

# Check key files
echo ""
echo "Checking key files..."

files=(
    "docker-compose.yml"
    "requirements.txt"
    "Makefile"
    "dbt/dbt_project.yml"
    "dbt/profiles.yml"
    "dags/dbt_analytics_dag.py"
)

for file in "${files[@]}"; do
    echo -n "  $file... "
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
done

# Check if .env exists
echo ""
echo -n "Checking .env file... "
if [ -f ".env" ]; then
    echo -e "${GREEN}✓ Exists${NC}"
else
    echo -e "${YELLOW}! Not found${NC}"
    echo -e "${YELLOW}  Run 'make init' to create it${NC}"
fi

# Check available disk space
echo ""
echo -n "Checking disk space... "
available_space=$(df -h . | awk 'NR==2 {print $4}')
echo -e "${GREEN}${available_space} available${NC}"

# Check if services are running
echo ""
echo "Checking running services..."
if docker compose ps 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}✓ Services are running${NC}"
    docker compose ps
else
    echo -e "${YELLOW}! Services are not running${NC}"
    echo -e "${YELLOW}  Run 'make up' to start services${NC}"
fi

echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Next Steps:${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

if [ ! -f ".env" ]; then
    echo -e "${YELLOW}1.${NC} Initialize the environment:"
    echo -e "   ${GREEN}make init${NC}"
    echo ""
fi

if ! docker compose ps 2>/dev/null | grep -q "Up"; then
    echo -e "${YELLOW}2.${NC} Start the services:"
    echo -e "   ${GREEN}make up${NC}"
    echo ""
fi

echo -e "${YELLOW}3.${NC} Access Airflow UI:"
echo -e "   ${GREEN}http://localhost:8080${NC}"
echo -e "   Username: ${GREEN}airflow${NC}"
echo -e "   Password: ${GREEN}airflow${NC}"
echo ""

echo -e "${YELLOW}4.${NC} Enable and run the DAG:"
echo -e "   Toggle on ${GREEN}dbt_analytics_pipeline${NC} and click play"
echo ""

echo -e "${YELLOW}5.${NC} Explore the data:"
echo -e "   ${GREEN}make duckdb-cli${NC}"
echo ""

echo -e "For help: ${GREEN}make help${NC}"
echo -e "Documentation: ${GREEN}cat README.md${NC}"
echo ""
