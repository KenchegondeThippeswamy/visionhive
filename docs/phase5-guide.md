# Phase 5: Data plane (RDS PostgreSQL, EFS, IAM policies per service)

Goal: add the data layer to the dev environment with Terraform, prove it works, and understand every piece.
Done when: you can connect to the database from inside the VPC, mount EFS, see one least-privilege IAM policy per service,
and you have destroyed and rebuilt the environment.

## 1. What this phase adds
| Piece | What it creates | Why |
|---|---|---|
| `modules/security` | 3 security groups: `app`, `rds`, `efs`. RDS accepts port 5432 only from `app`. EFS accepts port 2049 only from `app` | Only your workloads can reach the data. No CIDR ranges, no open ports |
| `modules/rds` | PostgreSQL 16 in the private subnets, encrypted, not public. Password is generated and stored in Secrets Manager by RDS | No password in code, Git or Terraform state |
| `modules/efs` | Encrypted file system, a mount target in each private subnet, an access point `/models`, lifecycle to Infrequent Access after 30 days | Shared model files for the workers |
| `modules/iam-policies` | One policy each for `upload-svc`, `ingest-worker` and External Secrets | Least privilege. They become IRSA roles in the EKS phase |
| `modules/bastion` | A tiny test instance in a public subnet, reached with AWS Systems Manager (no SSH, no inbound ports) | The only way to test private resources from inside the VPC |

Dev settings: single-AZ `db.t4g.micro`, 20 GB, 1 day of backups, no final snapshot, no deletion protection.
Prod settings: Multi-AZ `db.t4g.small`, 7 days of backups, deletion protection, a final snapshot, EFS backups, KMS key. Prod is only planned, never applied.

**Not in this phase:** the IAM roles themselves. A role for a Kubernetes service account needs the EKS cluster's OIDC provider, which does not exist yet.
So this phase creates the policies, and Phase 9 attaches them to IRSA roles.

## 2. Cost (read before you apply)
Check current prices for your region on the AWS pricing pages.
| Item | Cost behaviour |
|---|---|
| RDS `db.t4g.micro` | Billed per hour while it exists (a few cents per hour), plus storage. Stopped instances restart automatically after 7 days |
| Bastion `t3.micro` | Hourly, plus a small hourly charge for its public IPv4 address |
| EFS | Pennies per GB-month. Mount targets are free |
| Security groups, IAM policies | Free |

Rule: apply, test, write your notes, then destroy the same day. To remove only the expensive parts and keep the VPC:
```bash
terraform apply -var-file=env/dev.tfvars -var enable_rds=false -var enable_bastion=false
```
(`-var` must come after `-var-file`.)

## 3. Add the files to your repo
```bash
cd ~/Downloads/visionhive
git checkout dev && git pull
git checkout -b feature/phase5-data-plane
unzip -o ~/Downloads/visionhive-phase5.zip -d ~/Downloads/visionhive
ls terraform terraform/modules
./scripts/phase5-add-tfvars.sh
git status --short
```
Expected: `phase5.tf`, `phase5_variables.tf`, `phase5_outputs.tf` and five new folders under `modules/`
(`security rds efs iam-policies bastion`), plus changed `env/*.tfvars`.
No existing file is overwritten, so your region setting is safe.
There must be no `visionhive-phase5` folder inside the repo.

## 4. Build dev
```bash
cd ~/Downloads/visionhive/terraform
terraform fmt -recursive
terraform init -reconfigure -backend-config=env/dev.backend.hcl && terraform validate
terraform plan -var-file=env/dev.tfvars -out=dev.plan
```
How to read the plan:
- The Phase 5 resources number **20**: 6 security group resources, 2 RDS, 4 EFS, 3 IAM policies, 5 bastion.
- If dev is currently destroyed (it is, after the Phase 4 destroy), the plan also rebuilds the 28 base resources, so about **48 to add, 0 to change, 0 to destroy**.
- If dev was already rebuilt, you should see about **20 to add, 0 to destroy**.
- Any `destroy` or `replace` line means something is wrong. Stop and paste it.
```bash
time terraform apply dev.plan
terraform output
```
RDS takes roughly 5 to 10 minutes to create. If AWS rejects the instance class because of your plan or region, paste the error and we will pick another.

## 5. Verify in AWS
```bash
aws rds describe-db-instances --region ap-southeast-2 --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,EngineVersion,MultiAZ,StorageEncrypted,PubliclyAccessible]' --output table
aws efs describe-file-systems --region ap-southeast-2 --query 'FileSystems[].[FileSystemId,LifeCycleState,Encrypted]' --output table
aws iam list-policies --scope Local --query 'Policies[?contains(PolicyName,`visionhive-dev`)].PolicyName' --output text
aws secretsmanager list-secrets --region ap-southeast-2 --query 'SecretList[].Name' --output text
```
You want: status `available`, `StorageEncrypted True`, `PubliclyAccessible False`, three policy names, and an `rds!db-...` secret.
Read one policy to see least privilege:
```bash
aws iam get-policy --policy-arn $(terraform output -json service_policy_arns | python3 -c 'import sys,json;print(json.load(sys.stdin)["upload_svc"])') --query Policy.DefaultVersionId --output text
```
Then open the policy in the IAM console and confirm `upload-svc` can write only to `uploads/*` and send to one queue.

## 6. Connect to the database from inside the VPC
Install the Session Manager plugin on your laptop (once):
```bash
curl -s "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/ssm-plugin.deb
sudo dpkg -i /tmp/ssm-plugin.deb
session-manager-plugin --version
```
Wait 1 to 2 minutes after apply, then:
```bash
aws ssm describe-instance-information --region ap-southeast-2 --query 'InstanceInformationList[].InstanceId'
aws ssm start-session --region ap-southeast-2 --target $(terraform output -raw bastion_instance_id)
```
Inside the session (copy the endpoint and secret ARN from `terraform output`):
```bash
sudo dnf install -y postgresql16
export PGPASSWORD=$(aws secretsmanager get-secret-value --region ap-southeast-2 --secret-id '<rds_secret_arn>' --query SecretString --output text | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')
psql -h <rds_endpoint> -U visionhive_admin -d visionhive -c 'select version();'
```
Create the application tables (same SQL as Phase 1):
```bash
psql -h <rds_endpoint> -U visionhive_admin -d visionhive <<'SQL'
create table if not exists videos (
  id uuid primary key, filename text not null, s3_key text not null,
  status text not null default 'pending', created_at timestamptz not null default now());
create table if not exists detections (
  id serial primary key, video_id uuid references videos(id),
  label text not null, confidence real not null, frame int not null);
SQL
psql -h <rds_endpoint> -U visionhive_admin -d visionhive -c '\dt'
```
Type `exit` to leave the session.

## 7. Test EFS (inside the same session)
```bash
sudo dnf install -y amazon-efs-utils
sudo mkdir -p /mnt/models
sudo mount -t efs -o tls,accesspoint=<efs_access_point_id> <efs_id> /mnt/models
echo "model v1" | sudo tee /mnt/models/test.txt
ls -ln /mnt/models
df -h /mnt/models
```
The file shows owner `1000 1000` even though you wrote it as root. That is the access point forcing a fixed user, which is how pods get safe access later.

## 8. Break-fix labs (write each in docs/incidents/)
1. **Timeout to RDS.** Change the bastion's security group to the VPC's default group (console: instance, Security, Change security groups). `psql` now hangs. Read why (the `rds` group only trusts the `app` group), then restore it.
2. **Secret AccessDenied.** In the console delete the inline policy `read-db-secret` from the `visionhive-dev-bastion` role. `get-secret-value` fails with AccessDenied. Run `terraform apply` and watch Terraform restore it (drift).
3. **Storage cannot shrink.** Set `db_allocated_storage = 10`, run plan and apply, read the error, set it back to 20.
4. **Deletion protection.** Set `db_deletion_protection = true`, apply, then try `terraform destroy` and read the failure. Set it back to false, apply, then destroy.
5. **Snapshot restore** (optional, costs a little). Take a snapshot, delete a table, restore the snapshot to a new instance and compare:
```bash
aws rds create-db-snapshot --region ap-southeast-2 --db-instance-identifier visionhive-dev-postgres --db-snapshot-identifier lab-snap-1
aws rds wait db-snapshot-available --region ap-southeast-2 --db-snapshot-identifier lab-snap-1
aws rds restore-db-instance-from-db-snapshot --region ap-southeast-2 --db-instance-identifier lab-restore --db-snapshot-identifier lab-snap-1 \
  --db-subnet-group-name visionhive-dev-db --vpc-security-group-ids <rds_sg_id> --no-publicly-accessible --db-instance-class db.t4g.micro
```
Delete `lab-restore` and `lab-snap-1` afterwards (`aws rds delete-db-instance --skip-final-snapshot`, `aws rds delete-db-snapshot`), because manual copies are not managed by Terraform and keep billing.

## 9. Look at qa and prod without applying
```bash
terraform init -reconfigure -backend-config=env/prod.backend.hcl && terraform plan -var-file=env/prod.tfvars
terraform init -reconfigure -backend-config=env/dev.backend.hcl
```
In the prod plan find: `multi_az = true`, `deletion_protection = true`, a KMS key, and `final_snapshot_identifier`. Do not apply.

## 10. Destroy when you finish
```bash
terraform init -reconfigure -backend-config=env/dev.backend.hcl && terraform destroy -var-file=env/dev.tfvars
```
Dev has `db_skip_final_snapshot = true`, so the database goes without a snapshot.
Then check nothing is left: `aws rds describe-db-instances --region ap-southeast-2 --query 'DBInstances[].DBInstanceIdentifier'` should print `[]`, and `aws rds describe-db-snapshots --region ap-southeast-2 --snapshot-type manual` should list nothing you do not want.

## 11. Commit through a pull request
```bash
cd ~/Downloads/visionhive
git status --short           # no .tfstate, .terraform/ or .plan files
git add -A
git commit -m "feat: data plane (rds, efs, iam policies, bastion)"
git push -u origin feature/phase5-data-plane
gh pr create --base dev --head feature/phase5-data-plane --title "feat: data plane" --body "RDS, EFS, security groups, service IAM policies, SSM bastion"
```
Wait for `terraform-ci` (fmt and validate). Merge into `dev`, then `git checkout dev && git pull`.

## 12. Checklist
- [ ] Plan read: about 20 new resources for Phase 5, no destroys
- [ ] Apply finished, outputs shown
- [ ] RDS `available`, encrypted, not public; secret exists in Secrets Manager
- [ ] psql connected from the bastion, tables created
- [ ] EFS mounted, test file shows uid 1000
- [ ] Three service policies read in the console
- [ ] At least 3 labs done and written up
- [ ] qa and prod planned, not applied
- [ ] Everything destroyed, `describe-db-instances` is empty
- [ ] Pull request merged
