FROM apache/airflow:2.10.4-python3.11

USER root

ARG DUCKDB_VERSION=1.5.3

RUN apt-get update && \
    apt-get install -y --no-install-recommends unzip curl && \
    curl -fsSL "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip" \
        -o /tmp/duckdb.zip && \
    unzip /tmp/duckdb.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/duckdb && \
    rm /tmp/duckdb.zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install dbt in an isolated venv to avoid the protobuf conflict:
# opentelemetry-proto==1.27.0 (pinned by Airflow 2.10.4) requires protobuf<5.0
# dbt-core 1.9.x requires protobuf>=5.0 — mutually exclusive in a shared env.
# Cosmos calls dbt as a subprocess via dbt_executable_path, so no Python-level conflict.
RUN python3 -m venv /opt/dbt-venv && \
    /opt/dbt-venv/bin/pip install --no-cache-dir "dbt-duckdb==1.9.1" "dbt-core>=1.9.0,<1.10" && \
    chmod -R a+rx /opt/dbt-venv

USER airflow

COPY docker/requirements.txt /opt/airflow/requirements.txt
RUN --mount=type=cache,target=/home/airflow/.cache/pip \
    pip install -r /opt/airflow/requirements.txt
