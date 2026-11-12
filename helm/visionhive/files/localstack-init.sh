#!/bin/bash
set -e
awslocal s3 mb s3://visionhive-videos
awslocal sqs create-queue --queue-name visionhive-dlq
awslocal sqs create-queue --queue-name visionhive-jobs --attributes '{
  "VisibilityTimeout":"30",
  "RedrivePolicy":"{\"deadLetterTargetArn\":\"arn:aws:sqs:us-east-1:000000000000:visionhive-dlq\",\"maxReceiveCount\":\"3\"}"
}'
echo "LocalStack ready: bucket and queues created"
