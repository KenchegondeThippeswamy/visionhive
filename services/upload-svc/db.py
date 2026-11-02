import os
import psycopg2
from psycopg2.extras import RealDictCursor


def query(sql, params=None, fetch=True):
    conn = psycopg2.connect(
        host=os.getenv("DB_HOST", "postgres"),
        dbname=os.getenv("DB_NAME", "visionhive"),
        user=os.getenv("DB_USER", "visionhive"),
        password=os.getenv("DB_PASSWORD", "visionhive"),
        connect_timeout=5,
    )
    try:
        with conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            return cur.fetchall() if fetch else None
    finally:
        conn.close()

