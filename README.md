# VisionHive: AI video analysis platform (DevOps portfolio project)

Upload a video, a queue job is created, a worker "analyses" it, results are stored and monitored.
The services are intentionally simple. **The project is about the platform**: Docker, CI/CD, Terraform, EKS, GitOps, monitoring.

```
user -> api-gateway -> upload-svc -> S3 (presigned URL) + SQS
                                         |
                                  ingest-worker -> Postgres
Prometheus scrapes all 3 services -> Grafana
```

## STEP 0: Install tools (one time)
- Windows: install WSL2 (Ubuntu), then Docker Desktop with WSL integration. Mac/Linux: install Docker.
- Install Git, VS Code, Python 3. Check: `docker --version`, `git --version`.
- AWS: create an IAM user (never use root for work), enable MFA on root, install AWS CLI.
- **FIRST create an AWS Budget alert** (Billing > Budgets > $10 monthly, email alert). Do this before building anything on AWS.

## STEP 1: Run everything locally (Day 1, free)
```bash
git init && git add . && git commit -m "initial platform"
make up          # builds 3 images, starts Postgres, LocalStack (fake S3/SQS), Prometheus, Grafana
make ps          # all containers should be Up
make test        # runs the full flow, ends with JSON showing status "done" and detections
```
Open: Grafana http://localhost:3000 (admin/admin), Prometheus http://localhost:9090, API http://localhost:8080/docs

**Learn from this step:** read each Dockerfile line, run `docker logs`, `docker exec -it <container> sh`, open the Postgres tables.

**Mini tasks:**
1. In Prometheus run `worker_jobs_processed_total`, then `rate(gateway_requests_total[1m])`.
2. In Grafana (Dashboards > New) build a panel with `worker_jobs_in_progress`.
3. Run `make scale-workers` and send 10 test jobs. See jobs finish faster.

## STEP 2: Git and GitHub (Day 2)
- Create the GitHub repo, push `main`, create `dev` and `feature/*` branches.
- Add branch protection on `main` (PR required, CI must pass).
- Open a PR and watch `.github/workflows/ci.yml` build and Trivy-scan all 3 images.

## STEP 3: Break-fix labs, local (Day 3)
Write each in `docs/incidents/` (symptom, investigation, root cause, fix, prevention).
1. **Poison message:** `./scripts/smoke-test.sh corrupt.mp4` then watch the retries. After 3 failures the message lands in the DLQ. Check with LocalStack: `docker compose -f docker/docker-compose.yml exec localstack awslocal sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/visionhive-dlq --attribute-names ApproximateNumberOfMessages`
2. **DB down:** `docker compose -f docker/docker-compose.yml stop postgres`, call the API, read the errors, restart.
3. **Worker crash:** `docker kill` the worker mid-job and see the job reappear after the 30s visibility timeout.

## Roadmap (what we add next, in order)
| Step | What | Where | Cost |
|---|---|---|---|
| 4 | Terraform: S3 remote state, VPC, ECR | `terraform/` | ~free |
| 5 | Terraform: SQS, S3, KMS, RDS (dev.tfvars/qa/prod) | `terraform/` | small, destroy after |
| 6 | CI pushes images to ECR using GitHub OIDC (no keys) | `.github/workflows/` | free |
| 7 | Kubernetes locally on Minikube + raw manifests | `k8s/` | free |
| 8 | Helm chart with values per environment | `helm/` | free |
| 9 | EKS via Terraform + ALB Controller + ESO | `terraform/` | **paid**, destroy daily |
| 10 | Argo CD GitOps (dev/qa/prod) | `gitops/` | on EKS |
| 11 | Karpenter (spot) + KEDA scaling on SQS depth | `gitops/` | on EKS |
| 12 | kube-prometheus-stack, Grafana dashboards, alert rules | `monitoring/` | on EKS |
| 13 | CloudWatch alarm > SNS > Lambda enrichment | `monitoring/` | small |
| 14 | Jenkins + SonarQube + Nexus on EC2 via Ansible | `ansible/`, `jenkins/` | small, stop after |
| 15 | Serverless flow, ECS Fargate, CloudFormation, CodePipeline | various | small |
| 16 | Load test, spot interruption, DR runbook, demo video | `tests/`, `docs/` | EKS day |

## Cost rules for your $100 credits
1. Budget alert first. 2. Do steps 1-8 on your laptop (free). 3. Run EKS only on practice days (about $0.10/hour control plane, plus nodes and NAT). 4. Always `terraform destroy` before you stop. 5. Check the Billing dashboard every day.
