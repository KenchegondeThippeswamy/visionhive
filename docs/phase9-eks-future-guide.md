> **Historical reference only — not current deployment instructions.** This guide describes an earlier EKS design using IRSA/OIDC. The current Terraform implementation uses EKS Pod Identity. EKS deployment was blocked by AWS Organizations SCP restrictions, so no EKS cluster was created.

# Phase 9: EKS with Terraform

Goal: create an EKS cluster in the VPC from Phase 4, give each service only its own AWS permissions (IRSA), pull your CI-built images from ECR, and run the Phase 8 Helm chart against real S3, SQS and RDS behind an Application Load Balancer.
Done when: `./scripts/eks-test.sh` ends with `"status": "done"` through the ALB, `./scripts/verify-phase9.sh` says ALL GOOD, and after the teardown `./scripts/verify-phase9.sh --down` says ALL GOOD.

**THIS PHASE COSTS MONEY EVERY HOUR.** Plan one focused session (3 to 5 hours), then run `./scripts/eks-teardown.sh`. Part 11 lists every cost and the teardown order.

## 1. What you are building
| Piece | What it does |
|---|---|
| `terraform/eks/` (own state file `eks-dev`) | The cluster, one node group, the OIDC provider, the add-ons and the IAM roles. Separate from the environment stack so you can destroy it daily without touching RDS, ECR and the VPC |
| EKS cluster | Control plane managed by AWS. `upgrade_policy STANDARD` moves you to the next version before standard support ends, instead of expensive extended support |
| Node group `system` | 2 on-demand `t3.medium` nodes. By default in the public subnets with public IPs, so no NAT gateway is needed (cheaper). The cluster security group still blocks inbound traffic from the internet |
| OIDC provider and 5 IRSA roles | A pod exchanges its Kubernetes token for an IAM role. Roles: `ebs-csi`, `aws-load-balancer-controller`, `external-secrets`, `upload-svc`, `ingest-worker`. The last three attach the policies from Phase 5. `api-gateway` gets no role because it needs no AWS access |
| Add-ons | `vpc-cni`, `kube-proxy`, `coredns`, `metrics-server` (for the autoscaler), `aws-ebs-csi-driver` (disks, used in Phase 12) |
| Security group rule | The RDS group from Phase 5 only trusted the `app` group. This stack adds a rule so the cluster's group can reach port 5432. Without it the pods can never connect to the database |
| AWS Load Balancer Controller | Turns your Ingress into an Application Load Balancer |
| External Secrets Operator | Copies the RDS password from Secrets Manager into the Kubernetes Secret `db-credentials`, so no password is ever in Git |
| `scripts/eks-*.sh` | `up`, `bootstrap`, `deploy`, `test`, `teardown` |

Request path on EKS: you, ALB (accepts only your IP), Service, api-gateway pods, upload-svc (real S3 presigned URL and real SQS through its own IAM role), worker, RDS.

## 2. Before you start (the dev environment must be up with the database)
```bash
cd ~/Downloads/visionhive
git checkout dev && git pull
cd terraform
terraform init -reconfigure -backend-config=env/dev.backend.hcl && terraform plan -var-file=env/dev.tfvars -var enable_bastion=false -out=dev.plan
terraform apply dev.plan
cd ..
```
Read the plan first. This creates RDS (about 9 minutes, billed hourly) and the rest of dev. Then check:
```bash
aws ecr list-images --region ap-southeast-2 --repository-name visionhive-dev/api-gateway --query 'imageIds[].imageTag' --output text
aws rds describe-db-instances --region ap-southeast-2 --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus]' --output text
./scripts/verify-phase6.sh | tail -4
git log --oneline -3 -- helm/visionhive
```
You need: at least one image tag in ECR (merge to dev so CI pushes them), the database `available`, and the Phase 8 chart merged (`helm/visionhive` exists on dev). Tools: `aws`, `terraform`, `kubectl`, `helm` (installed in earlier phases).
Check the Kubernetes version EKS will use is in standard support (extended support costs several times more):
```bash
aws eks describe-cluster-versions --region ap-southeast-2 --query 'clusterVersions[].[clusterVersion,status,defaultVersion]' --output table
```
Leave `kubernetes_version` as `null` (EKS picks its default) unless you have a reason.

## 3. Add the files
Stand in the repo root. Do not use "Extract here" and do not add `-d`:
```bash
cd ~/Downloads/visionhive
git checkout -b feature/phase9-eks
unzip -o ~/Downloads/visionhive-phase9.zip
ls terraform/eks k8s-eks helm-values scripts
git status --short
```
Expected: `terraform/eks` has 9 `.tf` files and `policies/alb_iam_policy.json`; `k8s-eks` has 3 files; `helm-values` has 2; `scripts` has five `eks-*.sh` and `verify-phase9.sh`. `git status` shows `tf-ci.yml` as **modified** (it now also validates the other stacks) and everything else as new. There must be no `visionhive-phase9` folder in the repo. If there is, run `cp -a visionhive-phase9/. ./ && rm -rf visionhive-phase9`.

## 4. Create the cluster
```bash
./scripts/eks-up.sh
```
It checks the dev environment, runs `terraform plan` and shows it. Read it. The plan should say about **31 to add, 0 to change, 0 to destroy** (29 if the database does not exist). Type `yes` to apply. This takes 15 to 20 minutes. At the end `kubectl get nodes` shows 2 nodes `Ready`.
If it fails with an error about the remote state or missing outputs, the dev environment is not applied. If a Terraform argument is rejected, paste the whole error.

## 5. Install the controllers, the secret and the tables
```bash
./scripts/eks-bootstrap.sh
```
It installs the AWS Load Balancer Controller (chart 3.6.2) and External Secrets (chart 2.15.0), creates the `ClusterSecretStore` and the `ExternalSecret`, waits for `db-credentials`, then runs a one-off Job that creates the tables in RDS. The end of the output shows the Job's log (`CREATE TABLE`).

## 6. Deploy and test
```bash
./scripts/eks-deploy.sh
./scripts/eks-test.sh
```
`eks-deploy.sh` picks the newest image tag in ECR (or pass one), runs `helm upgrade --install` with `values-dev.yaml`, restricts the load balancer to **your own IP** and prints the ALB address. The first ALB needs 2 to 4 minutes before it answers. `eks-test.sh` waits for `/health` and then runs the end-to-end test with a real presigned upload to S3. It ends with `"status": "done"`.
If your public IP changes, re-run `./scripts/eks-deploy.sh` to update the allowed address.

## 7. Prove the identity model
```bash
kubectl -n visionhive exec deploy/upload-svc -- python -c "import boto3;print(boto3.client('sts',region_name='ap-southeast-2').get_caller_identity()['Arn'])"
kubectl -n visionhive get sa upload-svc -o jsonpath='{.metadata.annotations}'; echo
kubectl -n visionhive get pods -o wide
./scripts/verify-phase9.sh --test
```
The first command prints an `assumed-role/visionhive-dev-irsa-upload-svc/...` ARN. That is IRSA working: no keys anywhere, and the pod can only do what the Phase 5 policy allows.

## 8. Break-fix labs (write each in docs/incidents/)
1. **IRSA removed.** `kubectl -n visionhive annotate sa upload-svc eks.amazonaws.com/role-arn-` then `kubectl -n visionhive rollout restart deployment/upload-svc`. The pod falls back to the node's role. Run `./scripts/eks-test.sh`: the complete step fails. Read the AccessDenied in `kubectl -n visionhive logs deploy/upload-svc`. Fix with `./scripts/eks-deploy.sh` (it restores the annotation).
2. **Pending pods.** `kubectl -n visionhive set resources deployment/upload-svc --requests=cpu=3`. The pod stays Pending. `kubectl -n visionhive describe pod -l app=upload-svc` shows `Insufficient cpu`. Fix: `kubectl -n visionhive rollout undo deployment/upload-svc`.
3. **Unhealthy ALB target.** `kubectl -n visionhive annotate ingress api-gateway alb.ingress.kubernetes.io/healthcheck-path=/nope --overwrite`. Wait a minute: the ALB returns 503. Find the unhealthy targets in the EC2 console (target groups). Fix by setting it back to `/health`.
4. **Wrong database user.** `helm -n visionhive upgrade visionhive helm/visionhive -f helm/visionhive/values-dev.yaml --reuse-values --set database.user=wrong`. The readiness probe of api-gateway fails because `/ready` checks the database. Read the logs, then `helm -n visionhive rollback visionhive`.
5. **Node drain and the PodDisruptionBudget.** `kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data`, watch pods move, then `kubectl uncordon <node-name>`. Explain what the PDB (minAvailable 1) protected.
6. **Security group path.** In the EC2 console remove the rule "PostgreSQL from EKS nodes and pods" from the `visionhive-dev-rds` group. `/ready` starts failing. Run `terraform apply` in `terraform/eks` and watch Terraform restore it (drift).

## 9. Other things to try
- `kubectl get pods -A` and find every system pod.
- `kubectl get ingress,svc -n visionhive` and the ALB in the console. Find the target group and the targets (pod IPs, because of `target-type: ip`).
- `kubectl top nodes` and `kubectl top pods -n visionhive` (metrics-server).
- Hardening: set `api_allowed_cidrs=["YOUR_IP/32"]` in a `terraform.tfvars` file inside `terraform/eks` (do not commit it) and apply, to limit who can reach the Kubernetes API.

## 10. Teardown (the order matters)
```bash
./scripts/eks-teardown.sh
```
It removes the Helm release (which deletes the ALB), waits until the ALB and target groups are gone, warns about Karpenter nodes (Phase 11), removes the controllers, runs `terraform destroy` for the cluster stack, then runs `./scripts/verify-phase9.sh --down`. Then stop the paid parts of the environment:
```bash
cd terraform
terraform init -reconfigure -backend-config=env/dev.backend.hcl
terraform apply -var-file=env/dev.tfvars -var enable_rds=false -var enable_bastion=false
cd ..
./scripts/verify-phase5.sh --all-regions
```
Skipping the load balancer step leaves an ALB that keeps billing and blocks the VPC from being deleted. If `terraform destroy` hangs on a subnet or security group, look for a load balancer or a network interface left behind in the EC2 console.

## 11. Cost (check current prices)
| Item | Notes |
|---|---|
| EKS control plane | About 0.10 USD per hour while the cluster exists. Older Kubernetes versions in extended support cost several times more |
| 2 x t3.medium nodes | Hourly, plus two 20 GB disks |
| Application Load Balancer | Hourly plus usage |
| RDS | Hourly while it exists (switch it off after the session) |
| NAT gateway | **Not used**: nodes run in public subnets. Setting `private_nodes = true` needs `enable_nat_gateway = true` in dev, and a NAT bills hourly |
| Data transfer and logs | Small for this project. Control plane logging is off |
A four-hour session is a few dollars. Forgetting the cluster for a month costs more than your whole balance. Set a phone alarm for the stop time.

## 12. Security notes
- Nodes in public subnets have public IPs but the cluster security group allows inbound traffic only from inside the cluster. The ALB accepts only your IP. For a real system use private nodes with a NAT gateway or VPC endpoints.
- Nothing stores AWS keys. Pods use IRSA, the controllers use IRSA, and the database password comes from Secrets Manager through External Secrets.
- The Kubernetes API endpoint is public but needs IAM authentication. Restrict it with `api_allowed_cidrs` when you can.

## 13. Checklist
- [ ] Dev environment applied with RDS, images in ECR, Phase 8 chart merged
- [ ] Cluster created (about 31 resources), 2 nodes Ready
- [ ] Controllers installed, `db-credentials` created by External Secrets, tables created
- [ ] App deployed, ALB reachable only from your IP, `eks-test.sh` says status done
- [ ] IRSA proved with `get_caller_identity`, api-gateway has no role
- [ ] At least 3 labs written up
- [ ] **Teardown done** and `verify-phase9.sh --down` says ALL GOOD
- [ ] RDS switched off again and `verify-phase5.sh --all-regions` shows nothing running
- [ ] Pull request merged with a green `terraform-ci`

## 14. Commit
```bash
cd ~/Downloads/visionhive
git status --short
git add -A
git commit -m "feat: eks cluster, irsa roles, bootstrap and deploy scripts"
git push -u origin feature/phase9-eks
gh pr create --base dev --head feature/phase9-eks --title "feat: eks" --body "EKS stack, IRSA, controllers, scripts"
gh pr checks --watch
```
`git status --short` must not list `eks.plan`, `.terraform/` or `.tfstate`.

## 15. Interview questions
- What is IRSA, step by step? How does the pod get credentials and how does AWS decide which role it may assume?
- IRSA versus EKS Pod Identity.
- How does an Ingress become an ALB? What is `target-type: ip`?
- Why did the pods need an extra security group rule to reach RDS?
- Why does the cluster have its own Terraform stack and state file?
- What is the difference between the control plane and the data plane, and what do you pay for?
- Why are the nodes in public subnets here, and what would you change for production?
- Where does the database password come from, and why is it never in Git?
