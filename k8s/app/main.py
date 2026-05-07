import os
import psycopg2
from fastapi import FastAPI
from fastapi.responses import JSONResponse

# create the app
app = FastAPI(title="MovieRama API")

# database connection infos:
DB_HOST = os.getenv("DB_HOST", "postgres-primary.movierama.svc.cluster.local")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "movierama")
DB_USER = os.getenv("DB_USER", "movierama")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

def check_db_connection() -> bool:
    """Try to connect to the database. Returns True if successful, False if not."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5  # stop after 5m
        )
        conn.close()
        return True
    except Exception:
        return False

@app.get("/health")
def health():
    """
    Health endpoint - 
    Returns 200 if the app is running.
    """
    return JSONResponse(
        status_code=200,
        content={"status": "healthy"}
    )

@app.get("/ready")
def ready():
    """
    Readiness endpoint - 
    Eeturns 200 if app can reach the database.
    Returns 503 if database is unreachable.
    """
    if check_db_connection():
        return JSONResponse(
            status_code=200,
            content={"status": "ready", "database": "connected"}
        )
    else:
        return JSONResponse(
            status_code=503,
            content={"status": "not ready", "database": "unreachable"}
        )