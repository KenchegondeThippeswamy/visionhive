# Phase 4: Terraform (state bucket, VPC, ECR, S3, SQS, optional KMS)

Goal: create the AWS base for VisionHive with code, in 3 environments, with remote state.
Done when: `terraform apply` builds the dev environment, `terraform destroy` removes it, and state lives in S3.

Run Terraform on your LAPTOP (Ubuntu), not on the EC2 server.

## Part A: Credentials for Terraform (programmatic only, no console login)
Never create access keys for the root account.
1. IAM > Users > Create user. Name: `terraform-admin`. Do NOT enable console access.
2. Attach policy `AdministratorAccess` (fine for a personal learning account).
3. Open the user > Security credentials > Create access key > use case "Command Line Interface".
   Copy the Access key ID and Secret now (the secret is shown once). Do not commit or share it.
4. On your laptop:
```bash
aws configure --profile visionhive      # key, secret, region ap-south-1, output json
export AWS_PROFILE=visionhive
aws sts get-caller-identity             # must show user/terraform-admin
```
If your account blocks IAM users, use AWS CloudShell in the console as an alternative (no keys needed).

## Part B: Install Terraform (laptop)
```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
terraform -version            # must be 1.10 or newer
```

## Part C: Add the files to your repo
```bash
cd ~/Downloads && unzip visionhive-phase4.zip -d phase4-temp
cp -r phase4-temp/. ~/Pictures/visionhive/        # note the dot: it also copies .github
cd ~/Pictures/visionhive
git checkout dev && git pull
git checkout -b feature/phase4-terraform
ls terraform
```
Expected in `terraform/`: backend.tf main.tf outputs.tf variables.tf versions.tf bootstrap env modules.

**Region:** the code uses `ap-south-1` (Mumbai). If you use another region, change it in 3 places:
`terraform/variables.tf`, `terraform/bootstrap/main.tf`, and `region =` in the three `terraform/env/*.backend.hcl` files.
**Account ID:** `env/*.backend.hcl` contain `visionhive-tfstate-282380327737`. That must match your bucket name (printed by the bootstrap step).

## Part D: Bootstrap the state bucket (once)
```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply            # type yes
terraform output state_bucket
```
This uses local state on purpose (the bucket cannot store its own state before it exists).
Keep `terraform/bootstrap/terraform.tfstate` safe. It is in .gitignore.

## Part E: Build the dev environment
```bash
cd ../                        # now in terraform/
terraform fmt -recursive
terraform init -reconfigure -backend-config=env/dev.backend.hcl
terraform validate
terraform plan -var-file=env/dev.tfvars -out=dev.plan
terraform apply dev.plan
terraform output
```
Dev creates: VPC (10.10.0.0/16) with 2 public + 2 private subnets, internet gateway, S3 gateway endpoint,
3 ECR repositories, a versioned encrypted S3 videos bucket (Intelligent-Tiering), an SQS queue with a DLQ.
**Dev has no NAT gateway** (enable_nat_gateway = false) so it costs almost nothing.

Verify:
```bash
aws ec2 describe-vpcs --filters Name=tag:Project,Values=visionhive --query 'Vpcs[].[VpcId,CidrBlock]' --output table
aws ecr describe-repositories --query 'repositories[].repositoryName'
aws sqs list-queues
aws s3 ls | grep visionhive
aws s3 ls s3://visionhive-tfstate-282380327737/ --recursive    # your state file is here
```

## Part F: Switching environments
Each environment has its own state file. When you change env, re-init:
```bash
terraform init -reconfigure -backend-config=env/qa.backend.hcl
terraform plan -var-file=env/qa.tfvars
```
QA and prod enable NAT gateways (cost per hour). Do NOT apply them yet. Only plan them.
Prod also turns on KMS (customer managed key, about 1 USD per month) and IMMUTABLE ECR tags.

## Part G: Destroy
```bash
terraform init -reconfigure -backend-config=env/dev.backend.hcl
terraform destroy -var-file=env/dev.tfvars
```
dev has force_destroy = true so non-empty buckets and repos are removed.
Do not destroy the bootstrap bucket until the whole project ends.

## Part H: Commit through a pull request
```bash
cd ~/Pictures/visionhive
git add -A
git status                    # check: no .tfstate, no .terraform folders, no .plan files
git commit -m "feat: terraform base (vpc, ecr, s3, sqs, kms)"
git push -u origin feature/phase4-terraform
```
Open a PR into `dev`. The `terraform-ci` workflow runs fmt, validate and a report-only security scan.
Commit `.terraform.lock.hcl` (it pins provider versions). Never commit state, plans or .tfvars with secrets.
(Add `*.plan` to .gitignore.)

## How the code is organised
| Piece | Meaning |
|---|---|
| `bootstrap/` | creates the state bucket, local state |
| `backend.tf` + `env/*.backend.hcl` | tells Terraform to keep state in S3, one key per environment, S3 native locking |
| `variables.tf`, `env/*.tfvars` | same code, different values per environment |
| `main.tf` | calls the modules |
| `modules/vpc, ecr, s3, sqs, kms` | reusable building blocks |
| `count` and `for_each` | create N subnets, one repo per service, or nothing at all (NAT, KMS) |

## Break-fix labs (write each in docs/incidents/)
1. **Drift:** in the console, add a tag to the S3 videos bucket. Run `terraform plan` and read the diff. Apply to restore it.
2. **State lock:** run `terraform apply` in two terminals. The second waits or fails with a lock error. Read it.
3. **Bad CIDR:** set `vpc_cidr = "10.10.0.0/33"` in dev.tfvars, run plan, read the error, fix it.
4. **Immutable tags:** after you push an image later, push the same tag twice to a prod/qa repo. Read the ECR error.
5. **Delete by hand:** delete one subnet in the console, run plan, see Terraform plan to recreate it.
6. **Fmt failure:** break indentation in a .tf file, push, and see the CI fmt check fail. Fix with `terraform fmt -recursive`.

## Cost notes
VPC, subnets, IGW, S3 endpoint, ECR (small storage), SQS and S3 (small) are free or near free.
NAT gateway is the expensive one (hourly charge plus data). Keep it off until EKS needs it, then destroy after each session.
Set a budget alert and check Billing daily.

## Checklist
- [ ] terraform-admin user with programmatic access, profile `visionhive` works
- [ ] Terraform 1.10 or newer installed
- [ ] bootstrap applied, state bucket exists
- [ ] dev applied, outputs shown, resources visible in the console
- [ ] State file visible in the S3 state bucket
- [ ] dev destroyed and re-created once
- [ ] qa and prod plans read (not applied)
- [ ] PR merged with green terraform-ci
- [ ] 3+ incident notes
