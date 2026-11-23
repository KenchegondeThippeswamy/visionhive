# Phase 10: GitOps with Argo CD on Minikube

Goal: deploy by changing Git. Argo CD runs inside your Minikube cluster, watches the `dev` branch of your GitHub repository and applies the Helm chart. You never run `kubectl apply` or `helm upgrade` to release: you commit a new image tag.
Done when: a commit to `dev` rolls out new pods by itself, a manual change in the cluster is reverted by itself, and a bad commit is undone with `git revert`.
Cost: nothing extra. It runs on your laptop. This phase creates no AWS resources, so Terraform and its remote state are untouched.

## 1. How it fits your setup
| Your Phase 9 choice | In this phase |
|---|---|
| Kubernetes on local Minikube | Argo CD is installed in Minikube |
| Images in AWS ECR | Mode B pulls them from ECR with a pull secret. Mode A builds them inside Minikube (no ECR needed) |
| Terraform | Unchanged. Nothing here touches AWS infrastructure |
| Docker Compose | Compose stays for quick local runs. Releases now go through Git and Argo CD |
| GitHub Actions | Your `ci.yml` is **not changed**. An optional separate workflow can write the tag for you (part 10) |
| Prometheus and Grafana | Unchanged. The chart already has ServiceMonitors for later |
| S3, the Phase 5 RDS, Secrets Manager | Mode B uses them (part 9) |

## 2. How it works
```
you: build images, write the tag into gitops/local/values.yaml, git push to dev
                                              |
Argo CD (in Minikube) sees the new commit -> renders helm/visionhive + values-minikube.yaml + gitops/local/values.yaml -> applies it
```
| Piece | Purpose |
|---|---|
| `gitops/argocd/values.yaml` | Installs Argo CD (chart 10.18.0, Argo CD v3.6.1), small enough for a laptop |
| `gitops/bootstrap/project.yaml` | AppProject: only this repository, only the `visionhive` namespace, no cluster-wide objects |
| `gitops/bootstrap/root-app.yaml` | The app of apps. The only thing applied by hand. It deploys everything in `gitops/apps/` |
| `gitops/apps/visionhive-local.yaml` | The application: chart path, values files, automated sync with prune and self-heal |
| `gitops/local/values.yaml` | The image tag. The only value that changes on every release |
| `gitops/local/aws.values.yaml` | Mode B: real AWS services instead of LocalStack and the in-cluster database |
| `gitops/examples/visionhive-local-aws.yaml` | The mode B application. Move it to `gitops/apps/` to use it |
| `helm/visionhive/templates/deployments.yaml`, `values.yaml` | **Patched** chart files: new `image.pullSecrets` option so Minikube can pull from ECR |
| `scripts/gitops-local-up.sh` | Starts Minikube and installs Argo CD |
| `scripts/local-secrets.sh` | Creates the Secrets (never in Git) |
| `scripts/local-build-images.sh` | Builds the images inside Minikube and writes the tag |
| `scripts/gitops-set-tag.sh`, `gitops-ui.sh`, `gitops-down.sh`, `verify-phase10.sh` | Set a tag by hand, open the UI, tear down, verify |
| `.github/workflows/gitops-bump.yml` | Optional: writes the tag after CI succeeds (off by default) |

## 3. Two modes
| | Mode A (start here) | Mode B |
|---|---|---|
| Images | Built inside Minikube, tag = commit | ECR, pulled with the `ecr-pull` secret |
| Database | PostgreSQL in the cluster | The Phase 5 RDS |
| Queue and storage | LocalStack | Real SQS and S3 |
| Secrets | Random password, fake keys | Password from Secrets Manager, real keys |
| Needs AWS | No | Yes |
The Argo CD mechanics are the same in both. Learn them in mode A, then switch to mode B.

## 4. Before you start
- Minikube, `kubectl` and `helm` installed (earlier phases). Docker running.
- The Phase 8 chart merged on `dev`.
- Preserve the existing Phase 9 deployment and PostgreSQL PVC during migration. Do not run `helm-down.sh`, `k8s-down.sh`, or namespace deletion commands. Install Argo CD separately, adopt the existing Helm-managed resources carefully, and keep automated pruning disabled until resource ownership and health are verified.
- Memory: Argo CD plus the app need about 3 GB on top of Minikube's own use. `free -h` should show about 6 GB available, or start Minikube smaller with `MK_MEMORY=4096 MK_CPUS=2 ./scripts/gitops-local-up.sh`.

## 5. Add the files
Stand in the repo root. Do not use "Extract here" and do not add `-d`:
```bash
cd ~/Downloads/visionhive
git checkout dev && git pull
git checkout -b feature/phase10-gitops
unzip -o ~/Downloads/visionhive-phase10.zip
ls gitops gitops/apps gitops/local scripts
git status --short
```
Expected: `gitops/` has `argocd bootstrap apps local examples README.md`. `git status --short` shows `helm/visionhive/templates/deployments.yaml` and `helm/visionhive/values.yaml` as **modified** (the pull-secret patch) and the rest as new. There must be no `visionhive-phase10` folder in the repo. If there is, run `cp -a visionhive-phase10/. ./ && rm -rf visionhive-phase10`.

## 6. Merge it (Argo CD reads from GitHub)
```bash
git add -A
git commit -m "feat: argo cd gitops on minikube"
git push -u origin feature/phase10-gitops
gh pr create --base dev --head feature/phase10-gitops --title "feat: gitops with argo cd" --body "Argo CD, app of apps, chart pull-secret patch, scripts"
gh pr checks --watch
gh pr merge --merge --delete-branch
git checkout dev && git pull
```
`helm-ci` runs because the chart changed. It must be green.

## 7. Mode A, step by step
```bash
./scripts/gitops-local-up.sh
./scripts/local-secrets.sh
./scripts/local-build-images.sh
git add gitops/local/values.yaml
git commit -m "deploy: first release"
git push origin dev
```
1. `gitops-local-up.sh` starts Minikube, installs Argo CD with Helm, and applies the project and the app of apps.
2. `local-secrets.sh` creates `db-credentials` (random) and `aws-local-credentials` (fake LocalStack keys).
3. `local-build-images.sh` builds the three images **inside** Minikube tagged with the current commit and writes the tag into `gitops/local/values.yaml`.
4. Pushing that file is the release. (Pushing straight to `dev` is allowed here because only `main` is protected.)
Watch it deploy:
```bash
kubectl -n argocd get applications -w
kubectl -n visionhive get pods
```
Both applications become `Synced` and `Healthy` in a few minutes (Ctrl+C stops watching). If a pod shows `ImagePullBackOff` at first, wait: Argo CD may have synced before the images existed, and Kubernetes retries by itself. Then:
```bash
./scripts/gitops-ui.sh
```
It prints the user `admin` and the password, then opens the UI at http://localhost:8081. Click `visionhive-local` to see every object as a graph. In another terminal run the test (Phase 7 script):
```bash
./scripts/k8s-test.sh
./scripts/verify-phase10.sh
```
The test must end with `"status": "done"`.

## 8. Break-fix labs (write each in docs/incidents/)
1. **Self-heal.** `kubectl -n visionhive scale deployment upload-svc --replicas=3`. Watch `kubectl -n visionhive get pods -w`: Argo CD scales it back to 1 within a minute or two. Look at the history in the UI.
2. **Deploy by commit.** Make a visible change in `services/` (for example a comment) on a feature branch, merge it to `dev`, then `git pull`, run `./scripts/local-build-images.sh`, commit and push the tag file. Watch Argo CD roll the pods. You ran no `kubectl apply` and no `helm upgrade`. Compare `kubectl -n visionhive get deploy -o wide` with `git log -1 -- gitops/local/values.yaml`.
3. **Bad commit, then revert.** Set `tag: "nope"` in `gitops/local/values.yaml`, commit and push. The new pods stay in `ImagePullBackOff`, Argo CD shows `Degraded`, and the old pods keep serving (rolling update). Undo it with `git revert HEAD` and push. Watch it heal.
4. **Prune.** Add `services: {ingest-worker: {enabled: false}}` to `gitops/local/values.yaml`, push. Argo CD deletes the worker. Revert it.
5. **Project guard.** Copy `gitops/apps/visionhive-local.yaml` to a scratch file with a different `repoURL`, change the name, apply it with `kubectl apply -f`, and read the error in the application's conditions. Delete it afterwards.
6. **Drift of a ConfigMap.** `kubectl -n visionhive edit configmap app-config`, change `PROCESS_SECONDS`, save. Argo CD reverts it.
7. **Missing secret.** `kubectl -n visionhive delete secret db-credentials`. Pods that restart show `CreateContainerConfigError`. Recreate it with `./scripts/local-secrets.sh` (the existing random password will change, so `kubectl -n visionhive delete pod postgres-0` and recreate the data volume, or run `./scripts/gitops-down.sh` and start clean). Write down why secrets must be part of your recovery plan.

## 9. Mode B (AWS-backed)
Use it when you want ECR, real S3 and SQS, and the Phase 5 RDS. Three things must be true first:
1. The images exist in ECR with a tag you know (push them with the method you used in Phase 9).
2. Your pods can reach the database. RDS is in private subnets, so use the path you already built in Phase 9 and put its address in `gitops/local/aws.values.yaml` as `database.host` (it replaces `REPLACE_WITH_A_HOST_REACHABLE_FROM_PODS`).
3. The IAM user whose keys the pods use is **least privilege**: only the Phase 5 `upload-svc` and `ingest-worker` policies, never an administrator.
Then:
```bash
git checkout -b feature/gitops-mode-b
git mv gitops/examples/visionhive-local-aws.yaml gitops/apps/visionhive-local.yaml.new
git rm gitops/apps/visionhive-local.yaml
git mv gitops/apps/visionhive-local.yaml.new gitops/apps/visionhive-local.yaml
```
Edit `gitops/local/aws.values.yaml` (database host), then:
```bash
./scripts/gitops-set-tag.sh --ecr
./scripts/local-secrets.sh --aws --profile YOUR_LEAST_PRIVILEGE_PROFILE
git add -A && git commit -m "gitops: mode B (AWS-backed)" && git push -u origin feature/gitops-mode-b
gh pr create --base dev --head feature/gitops-mode-b --title "gitops: mode B" --body "ECR, S3, SQS, RDS"
gh pr merge --merge --delete-branch
```
`local-secrets.sh --aws` creates `db-credentials` from Secrets Manager, `ecr-pull` (an ECR login that lasts **12 hours**: run the script again to refresh it) and `aws-credentials` from the profile's keys after you type `yes`. Secret values go in through temporary files, never on a command line. If a profile uses SSO or a role it has no static keys, and the script tells you so.
In mode B the tag in `gitops/local/values.yaml` must be a tag that exists in ECR. Argo CD syncs from Git, so after merging, the old mode A resources (PostgreSQL, LocalStack) are removed by prune.

## 10. Optional: let GitHub write the tag
`.github/workflows/gitops-bump.yml` writes `gitops/local/values.yaml` after your `ci` workflow succeeds on `dev`. It is off by default so your working CI is never touched:
- Switch it on with the repository variable `GITOPS_BUMP=true` (Settings, Variables).
- GitHub only starts `workflow_run` workflows from the default branch, so it works after you merge `dev` into `main`.
- The tag is the first 7 characters of the commit. It must match the tag your CI pushes to ECR.
- You can also run it by hand from the Actions tab and type a tag.

## 11. Teardown
```bash
./scripts/gitops-down.sh --stop
```
It deletes the applications first (otherwise Argo CD recreates what you remove), uninstalls Argo CD, deletes both namespaces and stops Minikube. If you used mode B, nothing in AWS was created by this phase, but check that the RDS database and the bastion are switched off when you are done: `./scripts/verify-phase5.sh --all-regions`.

## 12. Troubleshooting
| You see | Meaning and fix |
|---|---|
| Application `ComparisonError`, "values file not found" or "path does not exist" | The files are not on the `dev` branch on GitHub yet. Merge part 6 first |
| `image.tag must be set` | The tag in `gitops/local/values.yaml` is empty. Run `./scripts/local-build-images.sh` or `./scripts/gitops-set-tag.sh abc1234` |
| `ImagePullBackOff` in mode A | The tag in Git does not match a built image. `minikube image ls \| grep visionhive` shows what exists. Re-run `local-build-images.sh` and push |
| `ImagePullBackOff` in mode B | The ECR secret expired (12 hours) or the tag is not in ECR. Run `./scripts/local-secrets.sh --aws` again and check the tag |
| `CreateContainerConfigError` | A Secret is missing. Run `./scripts/local-secrets.sh` |
| Application stays `OutOfSync` | Press Refresh in the UI. Argo CD checks Git about every 3 minutes |
| `Unable to connect to the repository` | A private repository needs a credential in Argo CD. Yours is public, so check the repo URL in `gitops/` |
| Port 8081 is busy | Another program uses it. Stop it or edit the port in `scripts/gitops-ui.sh` |
| Pods Pending, everything slow | Minikube is out of memory. Close other programs or free memory |
| Anything else | Paste the full error with the commands you ran |

## 13. Checklist
- [ ] Files merged to `dev` and `helm-ci` green
- [ ] Argo CD installed, `visionhive-root` and `visionhive-local` are Synced and Healthy
- [ ] `./scripts/k8s-test.sh` ends with status done
- [ ] Self-heal, deploy by commit and revert labs done and written up
- [ ] `./scripts/verify-phase10.sh` says ALL GOOD
- [ ] Optional: mode B working, optional bump workflow tried
- [ ] Minikube stopped with `./scripts/gitops-down.sh --stop`

## 14. Interview questions
- What is GitOps and what are its principles (declarative, versioned, pulled, continuously reconciled)?
- Pull versus push deployment: why does Argo CD need no cluster credentials in CI?
- What is the app-of-apps pattern, and when would you use an ApplicationSet instead?
- What do `prune` and `selfHeal` do? Why would production use a manual sync?
- Where do secrets live in a GitOps setup, and why are they not in the repository?
- How do you roll back? What does the revert look like in Argo CD?
- Why can a single `image.tag` line be the whole release?
