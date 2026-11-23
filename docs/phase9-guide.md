# Phase 9: Local Kubernetes Deployment and Monitoring

## Overview
VisionHive Phase 9 is deployed locally using Minikube and Helm.
AWS EKS deployment was blocked by AWS Organizations SCP restrictions.
The EKS implementation and original guide are preserved separately.

## 1. Environment
- Kubernetes: Minikube
- Deployment: Helm
- Application namespace: visionhive
- Monitoring namespace: monitoring

## 2. Application Components
- API Gateway
- Upload Service
- Ingest Worker
- PostgreSQL
- LocalStack

Build images and deploy using the project script:
- ./scripts/helm-up.sh

Helm chart: helm/visionhive/
Local values: helm/visionhive/values-minikube.yaml

## 3. Monitoring
Prometheus and Grafana are deployed in the monitoring namespace.
Configuration: monitoring/prometheus.yaml

Prometheus collects metrics from API Gateway, Upload Service,
Ingest Worker and Prometheus itself.

Prometheus access:
kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus 19090:9090
URL: http://localhost:19090

Grafana access:
kubectl port-forward --address 127.0.0.1 -n monitoring svc/grafana 3001:3000
URL: http://localhost:3001

Grafana dashboard: VisionHive Application Monitoring

Prometheus retention is 24 hours. Prometheus and Grafana currently
use emptyDir storage, so their stored data is not persistent.

## 4. Autoscaling
API Gateway HPA:
- Minimum replicas: 2
- Maximum replicas: 5
- CPU target: 50%

Check with:
kubectl get hpa -n visionhive
kubectl top nodes
kubectl top pods -n visionhive

## 5. End-to-End Verification
Run ./scripts/k8s-test.sh

The successful test registered and uploaded a video, queued a job,
processed it through the worker, updated PostgreSQL to done, and
returned detection results using LocalStack services.

## 6. Local Verification
Run ./scripts/verify-phase9-local.sh

This checks Minikube, node readiness, Helm, application pods,
monitoring pods, services and Prometheus targets when port-forwarding
is active.

## 7. Future AWS EKS Implementation
EKS Terraform files and scripts are retained for future use.
Required EKS operations were denied by AWS Organizations SCPs.
No EKS cluster or node group was created, and EKS Terraform apply
was not completed.

Original EKS guide: docs/phase9-eks-future-guide.md
EKS verifier: scripts/verify-phase9.sh

## 8. Verification Summary
- Minikube cluster: Passed
- Kubernetes node: Ready
- Helm release: Deployed
- VisionHive application pods: Running
- PostgreSQL and LocalStack: Running
- Prometheus and Grafana: Running
- Four Prometheus scrape targets: UP
- HPA and resource metrics: Available
- Video-processing end-to-end test: Successful

## 9. Important Notes
This is a local Kubernetes implementation, not a production EKS
deployment. Do not commit Terraform state, credentials, generated
secrets or local backups to Git.
