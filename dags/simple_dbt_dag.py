"""
Simple/testing DAG for running dbt with Cosmos.
Uses DbtTaskGroup inside a regular DAG so you can wrap it with custom tasks.
Each dbt model gets its own Airflow task automatically.

Pipeline:
  dbt_run (stg_customers, stg_orders, stg_lineitem → customer_orders, order_revenue)
"""

from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from cosmos import DbtTaskGroup, ExecutionConfig, ProfileConfig, ProjectConfig
from cosmos.constants import ExecutionMode

DBT_PROJECT_PATH = Path("/opt/airflow/dbt")

profile_config = ProfileConfig(
    profile_name="analytics",
    target_name="dev",
    profiles_yml_filepath=DBT_PROJECT_PATH / "profiles.yml",
)

default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="simple_dbt_pipeline",
    default_args=default_args,
    description="TPC-H → dbt pipeline: init data, then run staging + mart models",
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["dbt", "tpch", "duckdb"],
    max_active_runs=1,
    max_active_tasks=1,
) as dag:

    start = EmptyOperator(task_id="start")

    dbt_run = DbtTaskGroup(
        group_id="dbt_run",
        project_config=ProjectConfig(dbt_project_path=DBT_PROJECT_PATH),
        profile_config=profile_config,
        execution_config=ExecutionConfig(
            execution_mode=ExecutionMode.LOCAL,
            dbt_executable_path="/opt/dbt-venv/bin/dbt",
        ),
    )

    end = EmptyOperator(task_id="end")

    start >> dbt_run >> end
