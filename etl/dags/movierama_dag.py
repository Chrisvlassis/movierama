### --------------------------------------------------------- ###
### -------------------- MOVIERAMA DAG --------------------- ###
### --------------------------------------------------------- ###
# Orchestrates the MovieRama ETL pipeline using Apache Airflow.
# Runs every day at 6am.
# Flow:
#   1. Build latest Docker image
#   2. Run validation tests
#   3. Run ETL pipeline (only if tests pass)

from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import os


# --------------------------------------------------------- #
# Variables
# --------------------------------------------------------- #
default_args = {
    "retries":     1,                   # retry once if it fails
    "retry_delay": timedelta(minutes=5) # wait 5 mins before retry
}

# path to data folder on your Mac
DATA_PATH = os.environ.get(
    "MOVIERAMA_DATA_PATH",
    ""
)


# --------------------------------------------------------- #
# DAG DEFINITION
# --------------------------------------------------------- #
with DAG(
    dag_id="movierama_etl",
    description="MovieRama ETL Pipeline",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 6 * * *",  # every day at 6am
    catchup=False,
    tags=["movierama", "etl"],
) as dag:

    # --------------------------------------------------------- #
    # TASK 2 - run the ETL pipeline
    # --------------------------------------------------------- #
    run_etl = BashOperator(
        task_id="run_etl_pipeline",
        # we need :/data because that is the volume that is mounted in the Dockerfile and it has sample data
        bash_command=f"""
            docker run \
                -v {DATA_PATH}:/data \
                movierama-etl
        """,
    )

    # --------------------------------------------------------- #
    # run the ETL pipeline
    # --------------------------------------------------------- #
    run_etl