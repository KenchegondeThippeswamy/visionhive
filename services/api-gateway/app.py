import os
import time

import httpx
from fastapi import FastAPI, HTTPException, Request
from prometheus_client import Counter, Histogram, make_asgi_app

from db import query

UPLOAD_SVC = os.getenv("UPLOAD_SVC_URL", "http://upload-svc:8001")

app = FastAPI(title="api-gateway")
app.mount("/metrics", make_asgi_app())

REQS = Counter("gateway_requests_total", "HTTP requests", ["method", "path", "status"])
LATENCY = Histogram("gateway_request_seconds", "Request latency", ["path"])


@app.middleware("http")
async def metrics_mw(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    route = request.scope.get("route")
    path = route.path if route else request.url.path
    REQS.labels(request.method, path, response.status_code).inc()
    LATENCY.labels(path).observe(time.time() - start)
    return response


@app.get("/health")
def health():
    return {"status": "ok", "service": "api-gateway"}


@app.get("/ready")
def ready():
    try:
        query("select 1")
    except Exception as e:
        raise HTTPException(503, f"db not ready: {e}")
    return {"status": "ready"}


@app.post("/api/videos")
def create_video(body: dict):
    r = httpx.post(f"{UPLOAD_SVC}/upload-url", json=body, timeout=10)
    return r.json()


@app.post("/api/videos/{video_id}/complete")
def complete_video(video_id: str):
    r = httpx.post(f"{UPLOAD_SVC}/videos/{video_id}/complete", timeout=10)
    if r.status_code != 200:
        raise HTTPException(r.status_code, r.text)
    return r.json()


@app.get("/api/videos")
def list_videos():
    return query("select id::text, filename, status, created_at from videos order by created_at desc limit 50")


@app.get("/api/videos/{video_id}")
def get_video(video_id: str):
    rows = query("select id::text, filename, status, created_at from videos where id = %s", (video_id,))
    if not rows:
        raise HTTPException(404, "video not found")
    det = query("select label, confidence, frame from detections where video_id = %s order by frame", (video_id,))
    return {**rows[0], "detections": det}
