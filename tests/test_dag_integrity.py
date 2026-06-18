"""DAG parse tests — run inside the scheduler container.

Run with:
    docker compose exec airflow-scheduler python -m pytest /opt/airflow/tests/test_dag_integrity.py -v
"""
from pathlib import Path

from airflow.models import DagBag

DAGS_DIR = Path("/opt/airflow/dags")


def _dagbag():
    return DagBag(dag_folder=str(DAGS_DIR), include_examples=False)


def test_no_import_errors():
    errors = _dagbag().import_errors
    assert errors == {}, f"DAG import errors:\n{errors}"


def test_two_dags_loaded():
    assert len(_dagbag().dags) >= 2, "Expected at least 2 DAGs"


def test_analytics_pipeline_has_daily_schedule():
    dag = _dagbag().get_dag("dbt_analytics_pipeline")
    assert dag is not None, "dbt_analytics_pipeline DAG not found"
    # In Airflow 3.0 `schedule_interval` is gone; attribute is `schedule`
    assert str(dag.schedule) in ("@daily", "0 0 * * *"), \
        f"Unexpected schedule: {dag.schedule}"


def test_simple_pipeline_schedule_is_none():
    dag = _dagbag().get_dag("simple_dbt_pipeline")
    assert dag is not None, "simple_dbt_pipeline DAG not found"
    assert dag.schedule is None, f"Expected no schedule, got: {dag.schedule}"
