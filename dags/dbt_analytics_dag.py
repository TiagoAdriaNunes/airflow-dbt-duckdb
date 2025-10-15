"""
Airflow DAG for running dbt models with DuckDB using Astronomer Cosmos.

This DAG orchestrates the dbt analytics project, running staging models
followed by marts models.
"""

from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig, ExecutionMode

# Path configurations
DBT_PROJECT_PATH = Path("/opt/airflow/dbt")
DBT_PROFILES_PATH = Path("/opt/airflow/dbt")

# Default arguments for the DAG
default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

# Profile configuration for DuckDB - use profiles.yml file
profile_config = ProfileConfig(
    profile_name="analytics",
    target_name="dev",
    profiles_yml_filepath=str(DBT_PROFILES_PATH / "profiles.yml"),
)

# Project configuration
project_config = ProjectConfig(
    dbt_project_path=str(DBT_PROJECT_PATH),
)

# Execution configuration - use local execution mode
# dbt will be installed via _PIP_ADDITIONAL_REQUIREMENTS in docker-compose.yml
execution_config = ExecutionConfig(
    execution_mode=ExecutionMode.LOCAL,
)

with DAG(
    dag_id="dbt_analytics_pipeline",
    default_args=default_args,
    description="Run dbt models with DuckDB backend",
    schedule_interval="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["dbt", "analytics", "duckdb"],
    max_active_runs=1,  # Only one DAG run at a time
    max_active_tasks=1,  # Only one task at a time to avoid DuckDB lock conflicts
) as dag:

    start = EmptyOperator(task_id="start")

    # dbt task group using Cosmos
    # This will automatically create tasks for each model in the dbt project
    dbt_tg = DbtTaskGroup(
        group_id="dbt_transform",
        project_config=project_config,
        profile_config=profile_config,
        execution_config=execution_config,
        operator_args={
            "install_deps": True,  # Install dbt dependencies
        },
        default_args={
            "retries": 2,
        },
    )

    end = EmptyOperator(task_id="end")

    # Define task dependencies
    start >> dbt_tg >> end
