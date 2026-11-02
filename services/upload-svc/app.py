import json
import os
import uuid

import boto3
from botocore.config import Config
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, make_asgi_app
from pydantic import BaseModel

from db import query

REGION = os.getenv("AWS_REGION", "us-east-1")
BUCKET = os.getenv("S3_BUCKET", "visionhive-videos")
QUEUE_URL = os.getenv("QUEUE_URL", "")
# Empty endpoint = real AWS. Set to the LocalStack URL for local development.
S3_ENDPOINT = os.getenv("S3_ENDPOINT") or None
S3_PUBLIC_ENDPOINT = os.getenv("S3_PUBLIC_ENDPOINT") or S3_ENDPOINT
SQS_ENDPOINT = os.getenv("SQS_ENDPOINT") or None

cfg = Config(s3={"addressing_style": "path"})
s3_public = boto3.client("s3", region_name=REGION, endpoint_url=S3_PUBLIC_ENDPOINT, config=cfg)
sqs = boto3.client("sqs", region_name=REGION, endpoint_url=SQS_ENDPOINT)

app = FastAPI(title="upload-svc")
app.mount("/metrics", make_asgi_app())
UPLOADS = Counter("uploads_registered_total", "Videos registered")
JOBS = Counter("jobs_enqueued_total", "Jobs sent to SQS")


class UploadRequest(BaseModel):
    filename: str


@app.get("/health")
def health():
    return {"status": "ok", "service": "upload-svc"}


@app.post("/upload-url")
def upload_url(req: UploadRequest):
    vid = str(uuid.uuid4())
    key = f"uploads/{vid}/{req.filename}"
    query(
        "insert into videos(id, filename, s3_key, status) values (%s, %s, %s, 'pending')",
        (vid, req.filename, key),
        fetch=False,
    )
    url = s3_public.generate_presigned_url(
        "put_object", Params={"Bucket": BUCKET, "Key": key}, ExpiresIn=900
    )
    UPLOADS.inc()
    return {"video_id": vid, "upload_url": url}


@app.post("/videos/{video_id}/complete")
def complete(video_id: str):
    rows = query("update videos set status='queued' where id=%s returning s3_key", (video_id,))
    if not rows:
        raise HTTPException(404, "video not found")
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps({"video_id": video_id, "s3_key": rows[0]["s3_key"]}),
    )
    JOBS.inc()
    return {"video_id": video_id, "status": "queued"}
