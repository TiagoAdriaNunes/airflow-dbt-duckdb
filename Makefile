.PHONY: help init up down restart logs clean deep-clean dbt-run dbt-test dbt-debug dbt-deps lh-cli lh-query lh-explore lh-tables lh-orders lh-stats lh-recent lh-revenue

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

init: ## Initialize Airflow (run once before first start)
	@echo "$(YELLOW)Initializing Airflow...$(NC)"
	mkdir -p ./logs ./plugins ./data
	echo "AIRFLOW_UID=$$(id -u)" > .env
	cat .env.example >> .env
	docker compose up airflow-init
	@echo "$(GREEN)Initialization complete!$(NC)"

up: ## Start all services (webserver + scheduler only)
	@echo "$(YELLOW)Starting services... tach$(NC)"
	docker compose up -d airflow-webserver airflow-scheduler
	@echo "$(GREEN)Services started! Access Airflow at http://localhost:8080$(NC)"
	@echo "$(GREEN)Username: airflow | Password: airflow$(NC)"

down: ## Stop all services
	@echo "$(YELLOW)Stopping services...$(NC)"
	docker compose down
	@echo "$(GREEN)Services stopped!$(NC)"

restart: down up ## Restart all services

logs: ## View logs from all services
	docker compose logs -f

logs-airflow: ## View Airflow webserver logs
	docker compose logs -f airflow-webserver

logs-scheduler: ## View Airflow scheduler logs
	docker compose logs -f airflow-scheduler

clean: ## Remove all containers, volumes, and generated files
	@echo "$(YELLOW)Cleaning up...$(NC)"
	docker compose down -v
	rm -rf logs/* plugins/__pycache__
	@echo "$(GREEN)Cleanup complete!$(NC)"

deep-clean: ## Nuclear option: remove containers, volumes, built image, and Docker build cache
	@echo "$(YELLOW)Deep cleaning — removing containers, volumes, image, and build cache...$(NC)"
	docker compose down -v --rmi local
	docker builder prune -f
	rm -rf logs/* plugins/__pycache__
	@echo "$(GREEN)Deep clean complete. Run 'make init && make up' to start fresh.$(NC)"

DBT_DIR := /opt/airflow/dbt
DBT_BIN := /opt/dbt-venv/bin/dbt
DBT_ENV := DBT_PROFILES_DIR=$(DBT_DIR) DBT_TARGET=dev

dbt-deps: ## Install dbt dependencies
	@echo "$(YELLOW)Installing dbt dependencies...$(NC)"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) deps"

dbt-debug: ## Debug dbt connection
	@echo "$(YELLOW)Running dbt debug...$(NC)"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) debug"

dbt-run: ## Run all dbt models
	@echo "$(YELLOW)Running dbt models...$(NC)"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) run"

dbt-test: ## Run all dbt tests
	@echo "$(YELLOW)Running dbt tests...$(NC)"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) test"

dbt-seed: ## Load seed data
	@echo "$(YELLOW)Loading seed data...$(NC)"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) seed"

dbt-build: ## Run deps, seed, run, and test
	@echo "$(YELLOW)Building full dbt project...$(NC)"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) deps && $(DBT_BIN) seed && $(DBT_BIN) run && $(DBT_BIN) test"

dbt-docs-generate: ## Generate dbt documentation
	@echo "$(YELLOW)Generating dbt docs...$(NC)"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) docs generate"

dbt-docs-serve: ## Serve dbt documentation
	@echo "$(YELLOW)Serving dbt docs at http://localhost:8081$(NC)"
	docker compose exec -d airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) docs serve --port 8081"

lh-cli: ## Open DuckDB CLI attached to the lakehouse catalog (via PostgreSQL)
	@echo "$(YELLOW)Opening DuckDB CLI — type .quit to exit$(NC)"
	docker compose exec -it airflow-scheduler bash -c \
		"printf \"LOAD ducklake;\\nLOAD postgres;\\nATTACH 'ducklake:$${DUCKLAKE_CATALOG_CONN}' AS lakehouse;\\n\" \
		> /tmp/.lh_init.sql && duckdb -init /tmp/.lh_init.sql"

lh-query: ## Run custom SQL against the lakehouse (usage: make lh-query SQL="SELECT * FROM lakehouse.marts.customer_orders")
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py sql "$(SQL)"

lh-explore: ## Explore lakehouse data with menu
	@./explore_data.sh

lh-tables: ## List all schemas and tables in the lakehouse catalog
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py tables

lh-orders: ## Top 20 customers by spend
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py orders

lh-stats: ## Order statistics (count, total revenue, avg customer value)
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py stats

lh-recent: ## 10 most recent orders
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py recent

lh-revenue: ## Net revenue by market segment
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py revenue

airflow-cli: ## Open Airflow CLI
	docker compose exec airflow-webserver bash

install-deps: ## Install Python dependencies in running containers
	@echo "$(YELLOW)Installing Python dependencies...$(NC)"
	docker compose exec airflow-webserver pip install -r /opt/airflow/requirements.txt

ps: ## Show running containers
	docker compose ps

rebuild: ## Rebuild image (cached) and restart services
	@echo "$(YELLOW)Rebuilding services...$(NC)"
	docker compose down
	DOCKER_BUILDKIT=1 docker compose build
	$(MAKE) init
	$(MAKE) up
	@echo "$(GREEN)Services rebuilt and started!$(NC)"

rebuild-clean: ## Force full rebuild with no cache (slow — use after changing base image or apt deps)
	@echo "$(YELLOW)Force rebuilding services (no cache)...$(NC)"
	docker compose down
	DOCKER_BUILDKIT=1 docker compose build --no-cache
	$(MAKE) init
	$(MAKE) up
	@echo "$(GREEN)Services rebuilt and started!$(NC)"
