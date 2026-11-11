# Phase 6: CI pushes images to ECR with GitHub OIDC (no AWS keys)

Goal: every push to `dev` builds your three images, scans them with Trivy, and pushes them to the ECR repositories
that Terraform created, **without any AWS access key stored in GitHub**.
Done when: after a merge to `dev` the three images appear in ECR tagged with the commit, and you can explain why no key is needed.

## 1. How it works
```
GitHub Actions job (push to dev)
   | 1. asks GitHub for a short-lived OIDC token ("I am repo X, branch dev")
   v
AWS STS  --- checks the token against the OIDC provider and the role's trust rules --->
   | 2. returns temporary credentials (valid about 1 hour)
   v
docker push to ECR (visionhive-dev/<service>:<commit>)
```
| Piece | What it is |
|---|---|
| OIDC provider (AWS) | Tells AWS to trust tokens signed by `token.actions.githubusercontent.com` |
| IAM role `visionhive-github-actions-ecr` | The identity the job becomes. Its **trust policy** accepts only this repository and only the `dev` branch |
| Role permissions | Push and read images in `visionhive-dev/*` repositories only |
| Repository variable `AWS_ROLE_ARN` | The role's ARN. It is not a secret, only an identifier |
| `permissions: id-token: write` | Lets the job request the token. Without it, nothing works |

Why this beats access keys: a key is a password that lives forever and leaks easily. Here nothing is stored, the credentials expire in an hour, and the role cannot be assumed from a pull request or another branch or repository.

## 2. Before you start
```bash
cd ~/Downloads/visionhive
git checkout dev && git pull
gh pr list --state open
gh run list --branch dev --limit 3
aws ecr describe-repositories --region ap-southeast-2 --query 'repositories[].repositoryName' --output text
```
You need:
- Pull request #5 (Trivy tag and starlette upgrade) merged, and the latest `ci` run on `dev` green. If the scan is still red, Phase 6 cannot push anything.
- Three repositories listed: `visionhive-dev/api-gateway visionhive-dev/upload-svc visionhive-dev/ingest-worker`.

If the repositories are missing, the dev environment is destroyed. Rebuild the free base (no RDS, no bastion). **Always pass `-var-file`**: without it Terraform asks you for `var.vpc_cidr`, and typing `yes` there gives the error you saw earlier. If it ever prompts for a variable, press Ctrl+C.
```bash
cd ~/Downloads/visionhive/terraform
terraform init -reconfigure -backend-config=env/dev.backend.hcl && terraform apply -var-file=env/dev.tfvars -var enable_rds=false -var enable_bastion=false
```
Tip: leave this free base running permanently. VPC, ECR, S3 and SQS cost almost nothing, and CI can only push while the ECR repositories exist.

## 3. Add the files
```bash
cd ~/Downloads/visionhive
git checkout dev && git pull
git checkout -b feature/phase6-ecr-oidc
unzip -o ~/Downloads/visionhive-phase6.zip -d ~/Downloads/visionhive
ls terraform/github-oidc
ls .github scripts
git status --short
```
Expected: `terraform/github-oidc` has `main.tf outputs.tf variables.tf`. `.github` has `dependabot.yml` and `workflows`. `scripts` has `verify-phase6.sh`. `git status` shows `ci.yml` as **modified** (it is replaced) and the rest as new. There must be no `visionhive-phase6` folder inside the repo. If there is, run `cp -a visionhive-phase6/. ./ && rm -rf visionhive-phase6`.

The new `ci.yml` keeps your two earlier fixes (Trivy `v0.35.0`, `fail-fast: false`) and adds the ECR push.

## 4. Create the AWS side
```bash
cd ~/Downloads/visionhive/terraform/github-oidc
terraform init
terraform plan -out=oidc.plan
terraform apply oidc.plan
terraform output
```
- The plan should read **3 to add**: the OIDC provider, the role, and the role's inline policy.
- This folder has its own state file (`visionhive/github-oidc/terraform.tfstate`), so it survives when you destroy dev. Every variable has a default, so no `-var-file` is needed.
- If you get `EntityAlreadyExists` for the provider (an account can have only one), run `terraform apply -var create_oidc_provider=false`.
- Terraform prints `role_arn` and the `allowed_subjects`. Check the subject reads `repo:KenchegondeThippeswamy/visionhive:ref:refs/heads/dev`.

## 5. Tell GitHub the role ARN
```bash
gh variable set AWS_ROLE_ARN --body "$(terraform output -raw role_arn)"
gh variable list
```
Until this variable exists, the workflow still builds and scans but skips the push, so nothing breaks.

## 6. Commit and open the pull request
```bash
cd ~/Downloads/visionhive
git status --short
git add -A
git commit -m "feat: push images to ECR with GitHub OIDC"
git push -u origin feature/phase6-ecr-oidc
gh pr create --base dev --head feature/phase6-ecr-oidc --title "feat: ECR push with OIDC" --body "OIDC role, workflow push steps, dependabot"
gh pr checks --watch
```
`git status --short` must not list `oidc.plan`, `.terraform/` or `.tfstate` (they are ignored). On the pull request, the three `build-scan-push` jobs build and scan only. They never touch AWS, because the push steps require a push to `dev`.

When green, merge and watch the real push:
```bash
gh pr merge --merge --delete-branch
git checkout dev && git pull
gh run watch $(gh run list --branch dev --workflow ci --limit 1 --json databaseId --jq '.[0].databaseId')
```
In the run summary you should see `Pushed 282380327737.dkr.ecr.ap-southeast-2.amazonaws.com/visionhive-dev/<service>:<7 characters>` for each service.

## 7. Verify
```bash
SHORT=$(git rev-parse --short=7 HEAD)
for s in api-gateway upload-svc ingest-worker; do aws ecr list-images --region ap-southeast-2 --repository-name visionhive-dev/$s --query 'imageIds[].imageTag' --output text; done
echo "latest dev commit: $SHORT"
aws ecr describe-image-scan-findings --region ap-southeast-2 --repository-name visionhive-dev/api-gateway --image-id imageTag=$SHORT --query 'imageScanFindings.findingSeverityCounts'
```
Each repository lists a tag. The scan command shows ECR's own scan counts (a second opinion beside Trivy). If the newest commit was a docs-only change, its tag exists too, because every push to `dev` runs the workflow.

Pull one image and look inside, to prove it is the fixed one:
```bash
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 282380327737.dkr.ecr.ap-southeast-2.amazonaws.com
docker run --rm 282380327737.dkr.ecr.ap-southeast-2.amazonaws.com/visionhive-dev/api-gateway:$SHORT pip list 2>/dev/null | grep -iE "fastapi|starlette"
```
You should see `starlette 1.10.0`. Then run the one-command check:
```bash
./scripts/verify-phase6.sh
```

## 8. Security review (say this in an interview)
| Question | Answer |
|---|---|
| Where are the AWS keys? | There are none. GitHub issues a token per run and AWS exchanges it for credentials that last about an hour |
| Who can assume the role? | Only runs of `KenchegondeThippeswamy/visionhive` on the `dev` branch. Pull requests, other branches and other repositories are refused |
| What can the role do? | Log in to ECR and push or read images in `visionhive-dev/*`. It cannot touch S3, RDS, IAM or anything else |
| What if the workflow is changed on a feature branch? | The token's subject would be that branch, and AWS rejects it (lab 1) |
| Is the role ARN secret? | No. It is an identifier. The trust policy is what protects it |

## 9. Break-fix labs (write each in docs/incidents/)
1. **Wrong branch.** Create `lab-oidc`. In `ci.yml` change `branches: [main, dev]` to `branches: [main, dev, lab-oidc]` and `refs/heads/dev` to `refs/heads/lab-oidc`. Push the branch. The job fails at *Configure AWS credentials* with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. Read why (the trust policy lists only `dev`), then delete the branch. This shows that a changed workflow cannot grant itself access.
2. **Missing permission.** In the IAM console delete `ecr:PutImage` from the role's `ecr-push` policy. Re-run the job on `dev`. The push fails with `AccessDenied`. Run `terraform apply` in `terraform/github-oidc` and see Terraform restore it (drift).
3. **Repository missing.** Destroy dev (`terraform destroy -var-file=env/dev.tfvars` in `terraform/`), re-run CI. The push fails with `RepositoryNotFoundException`. Rebuild dev and re-run.
4. **Wrong variable.** `gh variable set AWS_ROLE_ARN --body arn:aws:iam::282380327737:role/nope`, re-run, read the error, then restore the real ARN.
5. **Scan gate.** On a feature branch add the line `requests==2.19.0` to `services/ingest-worker/requirements.txt` (an old release with known vulnerabilities). The Trivy source scan should fail the build. Revert it. If Trivy does not fail, tell me and we will pick another package.

## 10. Harden the workflow (recommended)
Tags like `@v4` can be moved, which is exactly how the Trivy action was attacked. Pin each action to the commit it points to and keep the version as a comment:
```bash
git ls-remote https://github.com/actions/checkout refs/tags/v4
git ls-remote https://github.com/aws-actions/configure-aws-credentials refs/tags/v4
git ls-remote https://github.com/aws-actions/amazon-ecr-login refs/tags/v2
git ls-remote https://github.com/aquasecurity/trivy-action refs/tags/v0.35.0
```
The first column is the commit SHA. Use it like this: `uses: actions/checkout@<40-character-sha> # v4`. If a command prints two lines, use the SHA of the line ending in `^{}`. The included `.github/dependabot.yml` then proposes updates to those pins and to your Python and Docker versions every week (as pull requests into `dev`).

## 11. Cost
OIDC, IAM roles and Actions on a public repository are free. ECR storage is billed per GB-month (check current pricing), and the lifecycle rule created in Phase 4 keeps only the last 20 images per repository.

## 12. Checklist
- [ ] Pull request #5 merged, `ci` on `dev` green
- [ ] OIDC provider, role and policy created (3 resources)
- [ ] `AWS_ROLE_ARN` repository variable set, no AWS keys in GitHub secrets
- [ ] Pull request run built and scanned without touching AWS
- [ ] After the merge, three images are in ECR with the commit tag
- [ ] You pulled an image and saw `starlette 1.10.0`
- [ ] At least 3 labs done and written up
- [ ] `./scripts/verify-phase6.sh` says ALL GOOD (or DONE with explained warnings)
- [ ] Optional: actions pinned to commit SHAs, Dependabot enabled

## 13. Interview questions
- What is OIDC, and why is it better than storing an access key in GitHub secrets?
- What do the `aud` and `sub` claims in the token mean, and where do you check them?
- Why does the pull request run not push images?
- What does `permissions: id-token: write` do?
- How do you stop a changed workflow from gaining access?
- Why tag images with the commit SHA instead of `latest`?
