#!/usr/bin/env bash
# Back up a directory to S3 and verify the upload.
# Usage: BUCKET=my-bucket ./backup-to-s3.sh /home/ubuntu/visionhive
# Needs: aws cli, and an IAM role (or credentials) allowed to write to the bucket.
set -euo pipefail

SRC=${1:?Usage: BUCKET=<bucket> $0 <directory>}
BUCKET=${BUCKET:?Set BUCKET=<your-bucket-name>}
HOST=$(hostname)
STAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE="/tmp/backup-${HOST}-${STAMP}.tar.gz"
KEY="backups/${HOST}/$(basename "$SRC")-${STAMP}.tar.gz"

cleanup() { rm -f "$ARCHIVE"; }
trap cleanup EXIT

[[ -d "$SRC" ]] || { echo "Source not found: $SRC"; exit 1; }

echo "Creating archive of $SRC"
tar -czf "$ARCHIVE" -C "$(dirname "$SRC")" "$(basename "$SRC")"

echo "Uploading to s3://$BUCKET/$KEY"
aws s3 cp "$ARCHIVE" "s3://$BUCKET/$KEY" --sse AES256

echo "Verifying upload"
aws s3 ls "s3://$BUCKET/$KEY"
echo "Backup OK: s3://$BUCKET/$KEY"
echo "Restore with: aws s3 cp s3://$BUCKET/$KEY . && tar -xzf $(basename "$KEY")"
