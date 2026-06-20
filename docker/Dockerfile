FROM apache/airflow:3.2.2-python3.11

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

USER airflow

COPY pyproject.toml uv.lock /opt/airflow/
# Build an isolated venv for extras (cosmos, dbt). Append it to sys.path via .pth
# so the base image's airflow/structlog always take precedence over the venv's copies.
RUN --mount=type=cache,target=/home/airflow/.cache/uv \
    UV_PYTHON_DOWNLOADS=never \
    uv sync --frozen --no-install-project --project /opt/airflow --python python3 && \
    echo "/opt/airflow/.venv/lib/python3.11/site-packages" \
        >> /home/airflow/.local/lib/python3.11/site-packages/airflow-extras.pth && \
    ln -s /opt/airflow/.venv/bin/dbt /home/airflow/.local/bin/dbt

# Base image ships protobuf 4.25.8 (uses old `including_default_value_fields` API).
# dbt-core 1.10+ calls MessageToJson(always_print_fields_with_no_presence=...) — the 5.x API name.
# Install 5.x to user site-packages (first in sys.path) to override the base image version.
RUN pip install "protobuf>=5.27.2,<7" --quiet
