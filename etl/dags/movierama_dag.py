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

# path to etl folder on your Mac
# used for building the image and mounting data
ETL_PATH = os.environ.get(
    "MOVIERAMA_ETL_PATH",
    ""
)

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
    # TASK 1 - build latest Docker image
    # Always builds fresh image before running
    # so we always use the latest code
    # --------------------------------------------------------- #
    build_image = BashOperator(
        task_id="build_docker_image",
        bash_command="""
            docker build -t movierama-etl /opt/movierama/etl
        """,
    )

    # --------------------------------------------------------- #
    # TASK 2 - run validation tests
    # Runs pytest against the freshly built image.
    # If tests fail, pipeline does not run.
    # --------------------------------------------------------- #
    run_tests = BashOperator(
        task_id="run_validation_tests",
        bash_command="""
            docker run \
                movierama-etl \
                pytest tests/test_validation.py -v
        """,
    )

    # --------------------------------------------------------- #
    # TASK 3 - run the ETL pipeline
    # Only runs if tests pass.
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
    # TASK ORDER
    # build → test → run
    # each step only runs if the previous one succeeded
    # --------------------------------------------------------- #
    build_image >> run_tests >> run_etl