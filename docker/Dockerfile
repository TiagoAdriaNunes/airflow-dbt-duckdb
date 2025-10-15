# Extended Airflow image with DuckDB CLI
# Python packages are installed at runtime via _PIP_ADDITIONAL_REQUIREMENTS
FROM apache/airflow:2.10.4-python3.11

USER root

# Install system dependencies and DuckDB CLI
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    unzip \
    && wget -q https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip \
    && unzip -q duckdb_cli-linux-amd64.zip \
    && mv duckdb /usr/local/bin/ \
    && chmod +x /usr/local/bin/duckdb \
    && rm duckdb_cli-linux-amd64.zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Verify DuckDB CLI is installed
RUN duckdb --version
