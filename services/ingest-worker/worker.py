"""Fake 'AI' worker: reads a job from SQS, pretends to analyse the video,
writes fake detections to Postgres. Used to practise queues, scaling and alerts."""
import json
import os
import random
import time

import boto3
from prometheus_client import Counter, Gauge, Histogram, start_http_server

from db import query

REGION = os.getenv("AWS_REGION", "us-east-1")
QUEUE_URL = os.getenv("QUEUE_URL", "")
SQS_ENDPOINT = os.getenv("SQS_ENDPOINT") or None
PROCESS_SECONDS = float(os.getenv("PROCESS_SECONDS", "5"))

sqs = boto3.client("sqs", region_name=REGION, endpoint_url=SQS_ENDPOINT)

PROCESSED = Counter("worker_jobs_processed_total", "Jobs finished", ["result"])
IN_PROGRESS = Gauge("worker_jobs_in_progress", "Jobs running now")
DURATION = Histogram("worker_job_seconds", "Job duration")

LABELS = ["person", "car", "bicycle", "dog", "truck"]


def process(body: dict):
    vid = body["video_id"]
    if "corrupt" in body.get("s3_key", ""):
        raise ValueError("corrupt video file")  # lab: poison message -> DLQ
    query("update videos set status='processing' where id=%s", (vid,), fetch=False)
    time.sleep(PROCESS_SECONDS)
    for frame in range(random.randint(3, 8)):
        query(
            "insert into detections(video_id, label, confidence, frame) values (%s,%s,%s,%s)",
            (vid, random.choice(LABELS), round(random.uniform(0.6, 0.99), 2), frame * 30),
            fetch=False,
        )
    query("update videos set status='done' where id=%s", (vid,), fetch=False)


def main():
    start_http_server(8000)
    print("worker started, waiting for jobs", flush=True)
    while True:
        try:
            resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=1, WaitTimeSeconds=5)
            for msg in resp.get("Messages", []):
                IN_PROGRESS.inc()
                with DURATION.time():
                    try:
                        process(json.loads(msg["Body"]))
                        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
                        PROCESSED.labels("ok").inc()
                    except Exception as e:
                        # not deleted -> returns to queue -> after 3 tries goes to the DLQ
                        print(f"job failed: {e}", flush=True)
                        PROCESSED.labels("error").inc()
                    finally:
                        IN_PROGRESS.dec()
        except Exception as e:
            print(f"loop error (retrying): {e}", flush=True)
            time.sleep(3)


if __name__ == "__main__":
    main()
