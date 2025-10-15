"""
Simple Airflow DAG for running dbt commands using BashOperator.

This is an alternative approach without using Cosmos, useful for
understanding the basic dbt commands being executed.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator

default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="simple_dbt_pipeline",
    default_args=default_args,
    description="Simple dbt pipeline using BashOperator",
    schedule_interval="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["dbt", "simple", "duckdb"],
    max_active_runs=1,  # Only one DAG run at a time
    max_active_tasks=1,  # Only one task at a time to avoid DuckDB lock conflicts
) as dag:

    start = EmptyOperator(task_id="start")

    # Install dbt dependencies
    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command="cd /opt/airflow/dbt && dbt deps",
    )

    # Run dbt seed to load CSV files
    dbt_seed = BashOperator(
        task_id="dbt_seed",
        bash_command="cd /opt/airflow/dbt && dbt seed",
    )

    # Run staging models
    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command="cd /opt/airflow/dbt && dbt run --select staging",
    )

    # Run marts models
    dbt_run_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command="cd /opt/airflow/dbt && dbt run --select marts",
    )

    # Run dbt tests
    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command="cd /opt/airflow/dbt && dbt test",
    )

    end = EmptyOperator(task_id="end")

    # Define task dependencies
    start >> dbt_deps >> dbt_seed
    dbt_seed >> dbt_run_staging >> dbt_run_marts >> dbt_test >> end
