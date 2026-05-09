# MovieRama - Senior SRE Data Engineer Assignment

## Overview
This repository contains the implementation of the MovieRama data platform assignment. It covers infrastructure provisioning, Kubernetes deployment, a production-grade Spark ETL pipeline, and orchestration.

```
movierama/
├── terraform/    # Task 1a - PostgreSQL primary/replica on Kubernetes
├── k8s/          # Task 1b - Web application deployment
├── etl/          # Task 2  - Spark ETL pipeline + Airflow orchestration
├── design/       # Task 3  - Design document
└── README.md
```

---

## Prerequisites

Make sure you have the following installed:

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | latest | https://www.docker.com/products/docker-desktop |
| Minikube | v1.38+ | `brew install minikube` |
| Terraform | v1.0+ | `brew install hashicorp/tap/terraform` |
| kubectl | latest | `brew install kubectl` |

---

## Task 1a — PostgreSQL Primary/Replica

We use **Terraform** to provision a PostgreSQL primary/replica setup with streaming replication on **Minikube (Kubernetes)**.

### How it works
```
postgres-primary-0  → accepts reads and writes
postgres-replica-0  → read-only, streams changes from primary
```

### Setup

**1. Start Minikube:**
```bash
minikube start
```

**Extra Note: Pull the postgress image & load it to minikube**
```bash
docker pull postgres:15
```
```bash
minikube image load postgres:15
```

**2. Initialize Terraform:**
```bash
cd terraform
terraform init
```

**3. Deploy:**
```bash
terraform apply
```

**4. Verify pods are running:**
```bash
kubectl get pods -n movierama
```

Expected output:
```
NAME                 READY   STATUS    RESTARTS   AGE
postgres-primary-0   1/1     Running   0          1m
postgres-replica-0   1/1     Running   0          1m
```

**5. Verify replication is working:**
```bash
# connect to primary and insert data
kubectl exec -it postgres-primary-0 -n movierama -- psql -U movierama -d movierama -c "CREATE TABLE test (id SERIAL, name TEXT); INSERT INTO test (name) VALUES ('replication works!');"

# connect to replica and verify data is there
kubectl exec -it postgres-replica-0 -n movierama -- psql -U movierama -d movierama -c "SELECT * FROM test;"
```

### Design Decisions
- Used **StatefulSets** instead of Deployments because databases need stable identity and persistent storage
- Used **Headless Services** for stable DNS names between pods
- Used **init container** on replica to run `pg_basebackup` before PostgreSQL starts
- Replication user has only `REPLICATION` privilege — follows least privilege principle
- Passwords stored in Kubernetes **Secrets**, never hardcoded

---

## Task 1b — Web Application

A **FastAPI** web application that communicates with the PostgreSQL primary and exposes health and readiness endpoints.

### Endpoints
| Endpoint | Returns | Description |
|----------|---------|-------------|
| `/health` | 200 | App process is running |
| `/ready` | 200 / 503 | 200 if DB reachable, 503 if not |

### Setup

**1. Make sure Task 1a is running first**

**2. Build the Docker image:**
```bash
cd k8s/app
docker build -t movierama-app:latest .
```

**3. Load image into Minikube:**
```bash
minikube image load movierama-app:latest
```

**4. Deploy to Kubernetes:**
```bash
cd k8s/manifests
kubectl apply -f .
```

**5. Get the URL:**
```bash
minikube service movierama-app -n movierama --url
```

**6. Test the endpoints:**
```bash
curl http://<url>/health
curl http://<url>/ready
```

### Design Decisions
- Used **Deployment** (not StatefulSet) because the web app is stateless
- Used **NodePort** service for local Minikube access
- **livenessProbe** on `/health` → Kubernetes restarts pod if app crashes
- **readinessProbe** on `/ready` → Kubernetes stops traffic if DB is unreachable
- DB password injected from existing **Secret** created in Task 1a

---

## Task 2 — Spark ETL Pipeline

A production-grade Spark ETL pipeline that processes MovieRama's movies and ratings data.

### Pipeline Flow
```
Extract  → read movies.csv + ratings.csv
           validate records (bad records → quarantine)
           handle schema evolution gracefully
           ↓
Transform → join movies + ratings using SparkSQL
            calculate avg rating per movie
            calculate ratings per genre
            add popularity category
            add genre rank
            ↓
Load     → write results as Parquet
           valid data  → data/output/
           bad records → data/output/quarantine/
```

### Setup

**1. Build the Docker image:**
```bash
cd etl
docker build -t movierama-etl .
```

**2. Run the pipeline:**
```bash
cd etl
docker run -v $(pwd)/data:/data movierama-etl
```

**3. Check the output:**
```bash
ls data/output/
```

### Running Unit Tests

Unit tests cover 100% of `validation.py` — the most critical part of the pipeline.

```bash
cd etl
docker run movierama-etl pytest tests/test_validation.py -v
```

Tests cover:
- Valid records pass through correctly
- Invalid types (integer, float, date, timestamp) are quarantined
- Null values are handled as valid business data
- Multiple invalid fields captured in quarantine reason
- Schema evolution: new columns ignored, missing columns filled with null
- Edge cases: empty DataFrame, all invalid records

> **Note:** Given more time, we would add unit tests for `extract.py` and `transform.py` as well, covering schema evolution handling, cast operations, and SparkSQL transformations. We would also add more data quality validations such as rating range checks (0-5), duplicate detection, and referential integrity between movies and ratings.

### Schema Evolution
The pipeline handles schema evolution gracefully:
- **New column appears** → logged as warning, ignored
- **Column goes missing** → logged as warning, filled with null
- **Wrong data type** → record quarantined with reason

**Alternative approach:** Instead of ignoring or filling missing columns, another strategy would be to dynamically adapt the pipeline on every run — read the incoming schema first, compare it against the expected schema, and automatically update the pipeline's schema definition to reflect the new structure. This would allow the pipeline to fully embrace schema changes rather than just tolerating them, at the cost of less predictability in downstream outputs. A solution would be using a glue crawler. 

### Design Decisions
- Read all data as **strings first** then validate types — prevents silent failures
- Bad records go to **quarantine** with reason — never silently dropped
- Output written as **Parquet** — industry standard, compressed, schema-aware
- Used **SparkSQL** for transformations — readable, maintainable
- Pipeline split into separate modules (`extract.py`, `transform.py`, `load.py`, `validation.py`) — single responsibility, easier to test and maintain

### Production Considerations
- Would run on **Databricks** instead of local Docker
- Would read from **PostgreSQL** (primary) and **MongoDB** directly
- Would write output to **S3** or a **data warehouse**
- Would add **data quality metrics** dashboard

---

## Task 2 (Bonus) — Airflow Orchestration

The ETL pipeline is orchestrated using **Apache Airflow**. It runs automatically every day at 6am.

### DAG Flow
```
Task 1: build_docker_image   → builds latest movierama-etl image
        ↓
Task 2: run_validation_tests → runs pytest against latest code
        ↓ (only if tests pass)
Task 3: run_etl_pipeline     → runs the ETL pipeline
```

If any task fails, the next task does not run. Airflow retries once after 5 minutes.

### Setup

**1. Copy environment file:**
```bash
cd etl
cp .env.example .env
```

**2. Edit `.env` and fill in your paths:**
```
AIRFLOW_UID=501                                    # run: id -u
MOVIERAMA_ETL_PATH=/your/full/path/to/movierama/etl
MOVIERAMA_DATA_PATH=/your/full/path/to/movierama/etl/data
```

**3. Initialize Airflow:**
```bash
docker compose up airflow-init
```

**4. Start Airflow:**
```bash
docker compose up
```

**5. Open Airflow UI:**
```
http://localhost:8080
username: airflow
password: airflow
```

**6. Trigger the DAG manually:**
- Find `movierama_etl` in the DAGs list
- Click the ▶️ button to trigger it

### DAG Details
- **Schedule:** Every day at 6am (`0 6 * * *`)
- **Retries:** 1 retry after 5 minutes if any task fails
- **Task 1:** Builds the latest Docker image from source
- **Task 2:** Runs validation tests — pipeline won't run if tests fail
- **Task 3:** Runs the ETL pipeline Docker container

---

## Task 2 (Bonus) — Spark Structured Streaming

A real-time streaming pipeline that watches for new rating files and processes them immediately.

### Setup

**1. Run the streaming pipeline:**
```bash
cd etl
docker run -v $(pwd)/data:/data movierama-etl python streaming.py
```

**2. Simulate a new ratings feed by dropping a file:**
```bash
cp data/streaming/incoming/ratings_batch_1.csv \
   data/streaming/incoming/ratings_batch_2.csv
```

**3. Check the output (within 10 seconds):**
```bash
ls data/streaming/output/
```

### How it works
- Watches `data/streaming/incoming/` for new CSV files
- Processes each file within 10 seconds of arrival
- Validates ratings (must be between 0-5)
- Appends valid records to `data/streaming/output/`
- Uses **checkpointing** to avoid reprocessing files on restart

### Production Considerations
- Would use **Apache Kafka** instead of file-based simulation
- Would run on a **Spark cluster** (AWS EMR, Databricks)

---

## Trade-offs and Assumptions

### Infrastructure
- Used **Minikube** instead of cloud provider for simplicity — same K8s concepts apply to AWS EKS or GCP GKE
- Used **Terraform** for IaC — reproducible, version controlled
- PostgreSQL passwords use simple defaults — in production would use **Vault** or AWS Secrets Manager

### ETL Pipeline
- Used **CSV files** as input instead of live databases — focuses on pipeline logic
- Used **local Parquet** as output instead of S3 — same code works with S3 by changing the path
- Used **Spark local mode** instead of cluster — same code runs on any Spark cluster
- Unit tests cover `validation.py` at 100% — given more time would extend to full pipeline coverage

### Streaming
- Used **file-based simulation** instead of Kafka — demonstrates streaming concepts without infrastructure overhead

### What Would Be Added Given More Time
- Unit tests for `extract.py`, `transform.py` and `load.py`
- More data quality validations (rating range, duplicate detection, referential integrity)
- Additional SparkSQL transformations (trending movies, user behaviour analysis)
- Observability: pipeline metrics, alerting on quarantine threshold
- CI/CD pipeline to automatically run tests on every push

### Observability
The pipeline currently provides basic observability through:
- **Logs** — every step logs progress and record counts
- **Quarantine files** — bad records stored with reason for inspection. Here we can use the afformentioned plus a  'select count(*) from {extracted_table}' and find out the failed records. 
- **Alerts** — Slack/email notifications when quarantine rate exceeds threshold
- **Airflow UI** — visual dashboard showing run history, success/failure
