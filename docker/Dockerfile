FROM apache/airflow:3.0.0-python3.11

USER root

ARG DUCKDB_VERSION=1.5.3

# uv binary — pinned version, no runtime download needed
COPY --from=ghcr.io/astral-sh/uv:0.11.21 /uv /uvx /usr/local/bin/

RUN apt-get update && \
    apt-get install -y --no-install-recommends unzip curl && \
    curl -fsSL "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip" \
        -o /tmp/duckdb.zip && \
    unzip /tmp/duckdb.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/duckdb && \
    rm /tmp/duckdb.zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV UV_LINK_MODE=copy

# Install dbt in an isolated venv to avoid the protobuf conflict:
# opentelemetry-proto (Airflow 2.10.4) pins protobuf<5; dbt-core>=1.9 requires protobuf>=5.
# Cosmos calls dbt as a subprocess via dbt_executable_path — no Python-level conflict.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /opt/dbt-venv && \
    uv pip install --python /opt/dbt-venv/bin/python \
        "dbt-duckdb==1.10.1" \
        "dbt-core==1.10.11" \
        "dbt-adapters==1.16.6" \
        "dbt-common==1.29.0" && \
    chmod -R a+rx /opt/dbt-venv

USER airflow

COPY docker/requirements.txt /opt/airflow/requirements.txt
RUN --mount=type=cache,target=/home/airflow/.cache/pip \
    pip install -r /opt/airflow/requirements.txt
