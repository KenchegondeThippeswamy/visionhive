#!/usr/bin/env bash
# Full flow: register video -> upload to S3 -> enqueue -> worker processes -> read results
set -euo pipefail
API=${API:-http://localhost:8080}
FILE=${1:-sample.mp4}
echo "fake video bytes" > /tmp/$FILE

RESP=$(curl -s -X POST "$API/api/videos" -H 'Content-Type: application/json' -d "{\"filename\":\"$FILE\"}")
ID=$(echo "$RESP"  | python3 -c 'import sys,json;print(json.load(sys.stdin)["video_id"])')
URL=$(echo "$RESP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["upload_url"])')
echo "1) registered video $ID"

curl -s -X PUT --upload-file /tmp/$FILE "$URL" && echo "2) uploaded to S3"
curl -s -X POST "$API/api/videos/$ID/complete" && echo && echo "3) job queued"
echo "4) waiting for worker..."; sleep 9
curl -s "$API/api/videos/$ID" | python3 -m json.tool
