.PHONY: help check-docker bootstrap init up down restart logs logs-airflow logs-scheduler clean deep-clean dbt-deps dbt-debug dbt-run dbt-test dbt-seed dbt-build dbt-docs-generate dbt-docs-serve lh-cli lh-query lh-tables lh-orders lh-stats lh-recent lh-revenue obs-build obs-up obs-down obs-logs obs-status logs-grafana logs-prometheus logs-otel logs-metrics logs-cadvisor pipeline-run airflow-cli ps rebuild rebuild-clean

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE  := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED   := \033[0;31m
NC    := \033[0m

check-docker: ## Verify Docker daemon is running
	@docker info > /dev/null 2>&1 || (printf "$(RED)Docker is not running. Please start Docker Desktop and try again.$(NC)\n" && exit 1)

help: ## Show this help message
	@printf "$(BLUE)Available commands:$(NC)\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;32m%-15s\033[0m %s\n", $$1, $$2}'

bootstrap: check-docker ## First-time setup: init Airflow, build images, start all services, run pipeline
	@printf "$(YELLOW)=== Step 1/4: Initializing Airflow ===$(NC)\n"
	$(MAKE) init
	@printf "$(YELLOW)=== Step 2/4: Building ducklake-metrics image ===$(NC)\n"
	@if docker image inspect airflow-dbt-duckdb-ducklake-metrics:latest > /dev/null 2>&1; then \
		printf "$(GREEN)Image already exists, skipping build$(NC)\n"; \
	else \
		DOCKER_BUILDKIT=1 docker compose build ducklake-metrics; \
	fi
	@printf "$(YELLOW)=== Step 3/4: Starting all services ===$(NC)\n"
	docker compose up -d airflow-webserver airflow-scheduler grafana otel-collector prometheus ducklake-metrics cadvisor
	@printf "$(YELLOW)Waiting for Airflow webserver to be ready...$(NC)\n"
	@until curl -sf http://localhost:8080/health > /dev/null 2>&1; do \
		printf "  still starting, retrying in 5s...\n"; sleep 5; \
	done
	@printf "$(GREEN)Airflow is ready!$(NC)\n"
	@printf "$(YELLOW)=== Step 4/4: Triggering dbt_analytics_pipeline ===$(NC)\n"
	$(MAKE) pipeline-run
	@printf "$(GREEN)=== Bootstrap complete! ===$(NC)\n"
	@printf "$(GREEN)Airflow:    http://localhost:8080  (airflow / airflow)$(NC)\n"
	@printf "$(GREEN)Grafana:    http://localhost:3000  (admin / admin)$(NC)\n"
	@printf "$(GREEN)Prometheus: http://localhost:9090$(NC)\n"
	@printf "$(YELLOW)Pipeline running - monitor at http://localhost:8080/dags/dbt_analytics_pipeline$(NC)\n"

init: check-docker ## Initialize Airflow (run once before first start)
	@printf "$(YELLOW)Initializing Airflow...$(NC)\n"
	mkdir -p ./logs ./plugins ./data
	cp .env.example .env
	docker compose up airflow-init
	@printf "$(GREEN)Initialization complete!$(NC)\n"

up: check-docker obs-build ## Start all services (Airflow + full observability stack)
	@printf "$(YELLOW)Starting services...$(NC)\n"
	docker compose up -d airflow-webserver airflow-scheduler grafana otel-collector prometheus ducklake-metrics cadvisor
	@printf "$(GREEN)Airflow:    http://localhost:8080  (airflow / airflow)$(NC)\n"
	@printf "$(GREEN)Grafana:    http://localhost:3000  (admin / admin)$(NC)\n"
	@printf "$(GREEN)Prometheus: http://localhost:9090$(NC)\n"

down: check-docker ## Stop all services
	@printf "$(YELLOW)Stopping services...$(NC)\n"
	docker compose down
	@printf "$(GREEN)Services stopped!$(NC)\n"

restart: down up ## Restart all services

logs: ## View logs from all services
	docker compose logs -f

logs-airflow: ## View Airflow webserver logs
	docker compose logs -f airflow-webserver

logs-scheduler: ## View Airflow scheduler logs
	docker compose logs -f airflow-scheduler

clean: check-docker ## Remove all containers, volumes, and generated files
	@printf "$(YELLOW)Cleaning up...$(NC)\n"
	docker compose down -v
	rm -rf logs/* plugins/__pycache__
	@printf "$(GREEN)Cleanup complete!$(NC)\n"

deep-clean: check-docker ## Nuclear option: remove containers, volumes, built image, and Docker build cache
	@printf "$(YELLOW)Deep cleaning — removing containers, volumes, image, and build cache...$(NC)\n"
	docker compose down -v --rmi local
	docker builder prune -f
	rm -rf logs/* plugins/__pycache__
	@printf "$(GREEN)Deep clean complete. Run 'make init && make up' to start fresh.$(NC)\n"

DBT_DIR := /opt/airflow/dbt
DBT_BIN := /opt/dbt-venv/bin/dbt
DBT_ENV := DBT_PROFILES_DIR=$(DBT_DIR) DBT_TARGET=dev

DUCKLAKE_CATALOG_CONN := postgres:dbname=ducklake_catalog host=postgres user=airflow password=airflow
DUCKLAKE_DATA_PATH    := /opt/warehouse/data

dbt-deps: check-docker ## Install dbt dependencies
	@printf "$(YELLOW)Installing dbt dependencies...$(NC)\n"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) deps"

dbt-debug: check-docker ## Debug dbt connection
	@printf "$(YELLOW)Running dbt debug...$(NC)\n"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) debug"

dbt-run: check-docker ## Run all dbt models
	@printf "$(YELLOW)Running dbt models...$(NC)\n"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) run"

dbt-test: check-docker ## Run all dbt tests
	@printf "$(YELLOW)Running dbt tests...$(NC)\n"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) test"

dbt-seed: check-docker ## Load seed data
	@printf "$(YELLOW)Loading seed data...$(NC)\n"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) seed"

dbt-build: check-docker ## Run deps, seed, run, and test
	@printf "$(YELLOW)Building full dbt project...$(NC)\n"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) deps && $(DBT_BIN) seed && $(DBT_BIN) run && $(DBT_BIN) test"

dbt-docs-generate: check-docker ## Generate dbt documentation
	@printf "$(YELLOW)Generating dbt docs...$(NC)\n"
	docker compose exec airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) docs generate"

dbt-docs-serve: check-docker ## Serve dbt documentation
	@printf "$(YELLOW)Serving dbt docs at http://localhost:8081$(NC)\n"
	docker compose exec -d airflow-scheduler bash -c "cd $(DBT_DIR) && $(DBT_ENV) $(DBT_BIN) docs serve --port 8081"

pipeline-run: check-docker ## Trigger the dbt_analytics_pipeline DAG (init TPC-H data + dbt models)
	@printf "$(YELLOW)Triggering dbt_analytics_pipeline DAG...$(NC)\n"
	docker compose exec -T airflow-webserver airflow dags trigger dbt_analytics_pipeline
	@printf "$(GREEN)DAG triggered — monitor at http://localhost:8080 (takes ~5-10 min)$(NC)\n"

lh-cli: check-docker ## Open DuckDB CLI attached to the lakehouse catalog (via PostgreSQL)
	@printf "$(YELLOW)Opening DuckDB CLI - type .quit to exit$(NC)\n"
	docker compose exec -it airflow-scheduler bash -c \
		"printf \"LOAD ducklake;\\nLOAD postgres;\\nATTACH 'ducklake:$(DUCKLAKE_CATALOG_CONN)' AS lakehouse (DATA_PATH '$(DUCKLAKE_DATA_PATH)');\\n\" \
		> /tmp/.lh_init.sql && duckdb -init /tmp/.lh_init.sql"

lh-query: check-docker ## Run custom SQL against the lakehouse (usage: make lh-query SQL="SELECT * FROM lakehouse.marts.customer_orders")
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py sql "$(SQL)"

lh-tables: check-docker ## List all schemas and tables in the lakehouse catalog
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py tables

lh-orders: check-docker ## Top 20 customers by spend
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py orders

lh-stats: check-docker ## Order statistics (count, total revenue, avg customer value)
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py stats

lh-recent: check-docker ## 10 most recent orders
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py recent

lh-revenue: check-docker ## Net revenue by market segment
	@docker compose exec -T airflow-scheduler python /opt/airflow/scripts/query_duckdb.py revenue

airflow-cli: check-docker ## Open a bash shell in the Airflow webserver container
	docker compose exec airflow-webserver bash

ps: ## Show running containers
	docker compose ps

rebuild: check-docker ## Rebuild Airflow image (cached) and restart services
	@printf "$(YELLOW)Rebuilding services...$(NC)\n"
	docker compose down
	DOCKER_BUILDKIT=1 docker compose build
	$(MAKE) up
	@printf "$(GREEN)Services rebuilt and started!$(NC)\n"

rebuild-clean: check-docker ## Force full rebuild with no cache (slow — use after changing base image or apt deps)
	@printf "$(YELLOW)Force rebuilding services (no cache)...$(NC)\n"
	docker compose down
	DOCKER_BUILDKIT=1 docker compose build --no-cache
	$(MAKE) up
	@printf "$(GREEN)Services rebuilt and started!$(NC)\n"

# ── Observability ────────────────────────────────────────────────────────────

obs-build: check-docker ## Build the ducklake-metrics image (runs automatically on make up)
	@printf "$(YELLOW)Building ducklake-metrics image...$(NC)\n"
	DOCKER_BUILDKIT=1 docker compose build ducklake-metrics
	@printf "$(GREEN)ducklake-metrics image ready$(NC)\n"

obs-up: check-docker ## Start only the observability stack (Grafana + OTEL + Prometheus + ducklake-metrics + cadvisor)
	@printf "$(YELLOW)Starting observability stack...$(NC)\n"
	docker compose up -d grafana otel-collector prometheus ducklake-metrics cadvisor
	@printf "$(GREEN)Grafana:    http://localhost:3000  (admin / admin)$(NC)\n"
	@printf "$(GREEN)Prometheus: http://localhost:9090$(NC)\n"

obs-down: check-docker ## Stop only the observability services
	@printf "$(YELLOW)Stopping observability stack...$(NC)\n"
	docker compose stop grafana otel-collector prometheus ducklake-metrics cadvisor
	docker compose rm -f grafana otel-collector prometheus ducklake-metrics cadvisor

obs-logs: check-docker ## Tail logs from all observability services
	docker compose logs -f grafana otel-collector prometheus ducklake-metrics cadvisor

logs-cadvisor: ## Tail cAdvisor logs
	docker compose logs -f cadvisor

obs-status: check-docker ## Show health of observability services and print first metric names
	@printf "$(BLUE)── Container status ─────────────────────────────────────$(NC)\n"
	@docker compose ps grafana otel-collector prometheus ducklake-metrics cadvisor
	@printf "\n"
	@printf "$(BLUE)── DuckLake metrics available in Prometheus ─────────────$(NC)\n"
	@docker compose exec -T prometheus wget -qO- 'http://localhost:9090/api/v1/label/__name__/values' 2>/dev/null \
		| python3 -c "import sys,json; names=[n for n in json.load(sys.stdin)['data'] if n.startswith('ducklake')]; print('\n'.join(names))" \
		|| printf "  (Prometheus not ready yet — wait ~60s after obs-up)\n"

logs-grafana: ## Tail Grafana logs
	docker compose logs -f grafana

logs-prometheus: ## Tail Prometheus logs
	docker compose logs -f prometheus

logs-otel: ## Tail OpenTelemetry Collector logs
	docker compose logs -f otel-collector

logs-metrics: ## Tail DuckLake metrics exporter logs
	docker compose logs -f ducklake-metrics
