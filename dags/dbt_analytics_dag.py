"""
Main production DAG: initializes TPC-H benchmark data, then runs all dbt models.
Each dbt model becomes its own Airflow task via Cosmos DbtTaskGroup.

Pipeline:
  init_tpch → dbt_run (stg_customers, stg_orders, stg_lineitem → customer_orders, order_revenue)
"""

import sys
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator
from cosmos import DbtTaskGroup, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from cosmos.constants import ExecutionMode, InvocationMode

sys.path.insert(0, "/opt/airflow/scripts")

DBT_PROJECT_PATH = Path("/opt/airflow/dbt")
DBT_EXECUTABLE_PATH = Path("/opt/airflow/.venv/bin/dbt")

profile_config = ProfileConfig(
    profile_name="analytics",
    target_name="dev",
    profiles_yml_filepath=DBT_PROJECT_PATH / "profiles.yml",
)

default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=1),
}

with DAG(
    dag_id="dbt_analytics_pipeline",
    default_args=default_args,
    description="TPC-H → dbt pipeline: init DuckLake data, then run staging + mart models",
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["dbt", "analytics", "duckdb"],
    max_active_runs=1,
) as dag:

    start = EmptyOperator(task_id="start")

    def _init_tpch():
        from init_tpch import init_tpch
        init_tpch()

    init_tpch_task = PythonOperator(
        task_id="init_tpch",
        python_callable=_init_tpch,
    )

    dbt_run = DbtTaskGroup(
        group_id="dbt_run",
        project_config=ProjectConfig(dbt_project_path=DBT_PROJECT_PATH),
        profile_config=profile_config,
        execution_config=ExecutionConfig(
            execution_mode=ExecutionMode.LOCAL,
            invocation_mode=InvocationMode.SUBPROCESS,
            dbt_executable_path=DBT_EXECUTABLE_PATH,
        ),
        render_config=RenderConfig(
            invocation_mode=InvocationMode.SUBPROCESS,
            select=["resource_type:model"],
        ),
    )

    end = EmptyOperator(task_id="end")

    start >> init_tpch_task >> dbt_run >> end
