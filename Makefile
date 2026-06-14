.PHONY: help init up down restart logs clean dbt-run dbt-test dbt-debug dbt-deps duckdb-cli duckdb-query duckdb-explore duckdb-show-tables duckdb-customer-orders duckdb-stats duckdb-recent

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

DBT_DIR := /opt/airflow/dbt
DBT_ENV := DBT_PROFILES_DIR=$(DBT_DIR) DBT_TARGET=dev

dbt-deps: ## Install dbt dependencies
	@echo "$(YELLOW)Installing dbt dependencies...$(NC)"
	docker compose exec airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt deps"

dbt-debug: ## Debug dbt connection
	@echo "$(YELLOW)Running dbt debug...$(NC)"
	docker compose exec airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt debug"

dbt-run: ## Run all dbt models
	@echo "$(YELLOW)Running dbt models...$(NC)"
	docker compose exec airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt run"

dbt-test: ## Run all dbt tests
	@echo "$(YELLOW)Running dbt tests...$(NC)"
	docker compose exec airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt test"

dbt-seed: ## Load seed data
	@echo "$(YELLOW)Loading seed data...$(NC)"
	docker compose exec airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt seed"

dbt-build: ## Run deps, seed, run, and test
	@echo "$(YELLOW)Building full dbt project...$(NC)"
	docker compose exec airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt deps && dbt seed && dbt run && dbt test"

dbt-docs-generate: ## Generate dbt documentation
	@echo "$(YELLOW)Generating dbt docs...$(NC)"
	docker compose exec airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt docs generate"

dbt-docs-serve: ## Serve dbt documentation
	@echo "$(YELLOW)Serving dbt docs at http://localhost:8081$(NC)"
	docker compose exec -d airflow-webserver bash -c "cd $(DBT_DIR) && $(DBT_ENV) dbt docs serve --port 8081"

duckdb-cli: ## Open DuckDB CLI (interactive shell)
	@echo "$(YELLOW)Opening DuckDB CLI — type .quit to exit$(NC)"
	docker compose exec -it airflow-webserver duckdb /opt/warehouse/warehouse.duckdb

duckdb-clear-lock: ## Clear stale DuckDB lock (PID 0 / orphaned lock from killed process)
	@echo "$(YELLOW)Clearing stale DuckDB lock...$(NC)"
	@docker compose exec -T airflow-scheduler bash -c " \
		cp /opt/warehouse/warehouse.duckdb /opt/warehouse/warehouse.duckdb.bak && \
		rm /opt/warehouse/warehouse.duckdb && \
		mv /opt/warehouse/warehouse.duckdb.bak /opt/warehouse/warehouse.duckdb"
	@echo "$(GREEN)Lock cleared. Run 'make dbt-seed && make dbt-run' to repopulate data.$(NC)"

duckdb-query: ## Run custom DuckDB SQL query (usage: make duckdb-query SQL="SELECT * FROM main_marts.customer_orders")
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py sql "$(SQL)"

duckdb-explore: ## Explore DuckDB data with menu
	@./explore_data.sh

duckdb-show-tables: ## Show all DuckDB tables
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py tables

duckdb-customer-orders: ## Show customer orders data
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py orders

duckdb-stats: ## Show order statistics
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py stats

duckdb-recent: ## Show recent orders
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py recent

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
