import os
import time
from flask import Flask, jsonify
import psycopg2

app = Flask(__name__)

APP_MESSAGE = os.environ.get("APP_MESSAGE", "Hello World")
DB_HOST = os.environ.get("DB_HOST", "postgres")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")


def get_db_connection(retries=3, delay=2):
    last_err = None
    for _ in range(retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                port=DB_PORT,
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD,
                connect_timeout=3,
            )
            return conn
        except Exception as e:  # noqa: BLE001
            last_err = e
            time.sleep(delay)
    raise last_err


@app.route("/")
def index():
    return jsonify(message=APP_MESSAGE)


@app.route("/health")
def health():
    # Liveness: process is up
    return jsonify(status="ok"), 200


@app.route("/ready")
def ready():
    # Readiness: can we reach the DB
    try:
        conn = get_db_connection(retries=1, delay=0)
        conn.close()
        return jsonify(status="ready", db="reachable"), 200
    except Exception as e:  # noqa: BLE001
        return jsonify(status="not-ready", db="unreachable", error=str(e)), 503


@app.route("/db-time")
def db_time():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT NOW();")
        result = cur.fetchone()[0]
        cur.close()
        conn.close()
        return jsonify(db_time=str(result))
    except Exception as e:  # noqa: BLE001
        return jsonify(error=str(e)), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
