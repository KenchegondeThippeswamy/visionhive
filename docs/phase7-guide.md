# Phase 7: Kubernetes on Minikube (raw manifests)

Goal: run all of VisionHive in a real Kubernetes cluster on your laptop, using plain manifests, so Phases 9 to 11 (EKS, Argo CD, Karpenter) hold no surprises.
Done when: `./scripts/k8s-test.sh` ends with `"status": "done"`, the autoscaler reacts to load, and you have broken and fixed at least four things on purpose.
Cost: nothing. It all runs on your laptop.

## 1. Concepts you will use
| Object | What it does in this project | File |
|---|---|---|
| Namespace | A named box that groups everything (`visionhive`) | `namespace.yaml` |
| Pod | One or more containers that run together. You rarely create these by hand | made by the controllers below |
| Deployment (and ReplicaSet) | Keeps N identical pods running, replaces dead ones, does rolling updates and rollbacks | `api-gateway.yaml`, `upload-svc.yaml`, `ingest-worker.yaml`, `localstack.yaml` |
| StatefulSet | Like a Deployment but with stable names and its own disk. Used for the database | `postgres.yaml` |
| Service | A stable name and IP in front of changing pods. `postgres`, `localstack`, `upload-svc` are DNS names inside the cluster | each manifest |
| Ingress | HTTP entry from outside to a Service (host `visionhive.local`) | `ingress.yaml` |
| ConfigMap | Non-secret settings (`app-config`) and the init scripts | `configmap.yaml`, `files/` |
| Secret | Passwords. Created by the script, never stored in Git | `scripts/k8s-up.sh` |
| PVC | A disk request. The database keeps its data across pod restarts | `postgres.yaml` |
| Probes | `readiness` decides if a pod gets traffic, `liveness` decides if it must be restarted | each Deployment |
| Requests and limits | The CPU and memory a pod is promised and the most it may use | each Deployment |
| HPA | Adds or removes api-gateway pods based on CPU | `hpa.yaml` |
| PodDisruptionBudget | Keeps at least 1 api-gateway pod up during maintenance | `pdb.yaml` |
| Kustomize | `kubectl apply -k k8s` applies the whole folder and turns the two script files into ConfigMaps | `kustomization.yaml` |

How the pieces connect:
```
you -> Ingress (visionhive.local) -> Service api-gateway -> 2 pods (HPA: 2 to 5)
                                        api-gateway -> Service upload-svc -> pod -> LocalStack (S3 + SQS) 
                                                                              \-> StatefulSet postgres (PVC)
                                        ingest-worker pod <- queue visionhive-jobs (LocalStack) -> postgres
```
LocalStack stands in for S3 and SQS and Postgres stands in for RDS. In Phase 9 those become the real AWS services.

## 2. Install the tools (once)
Check your CPU first: `uname -m` should print `x86_64`. If it prints `aarch64`, replace `amd64` with `arm64` below.
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
kubectl version --client
minikube version
free -h
```
Minikube needs about 6 GB of free memory (see the `Mem:` line under `available`). If you have less, run `MK_MEMORY=4096 MK_CPUS=2 ./scripts/k8s-up.sh`.

## 3. Add the files
First finish Phase 6 (or at least merge it), then:
```bash
cd ~/Downloads/visionhive
git checkout dev && git pull
git checkout -b feature/phase7-kubernetes
unzip -o ~/Downloads/visionhive-phase7.zip -d ~/Downloads/visionhive
ls k8s k8s/files scripts
git status --short
```
Expected: `k8s` has 11 files plus `files/`, and `scripts` has `k8s-up.sh k8s-test.sh k8s-down.sh verify-phase7.sh`. There must be no `visionhive-phase7` folder inside the repo. If there is, run `cp -a visionhive-phase7/. ./ && rm -rf visionhive-phase7`.

## 4. Stop the Docker Compose stack
Both stacks want ports 8080 and 4566 (and Compose already clashed on 9090 earlier):
```bash
make down
```

## 5. Start the cluster and deploy
```bash
./scripts/k8s-up.sh
```
It starts Minikube, enables the ingress controller and metrics server, builds the three images **inside** Minikube (so no registry is needed), creates the two secrets, applies `k8s/`, and waits until everything is ready. The first run takes 5 to 10 minutes (downloads). If it fails, read the last lines, fix, and run it again, it is safe to repeat.

Look at what you built:
```bash
kubectl -n visionhive get all
kubectl -n visionhive get pvc,ingress,hpa,pdb,configmap,secret
kubectl get nodes -o wide
```
Make `visionhive` your default namespace so you can drop `-n visionhive`:
```bash
kubectl config set-context --current --namespace=visionhive
```

## 6. Test the application
```bash
./scripts/k8s-test.sh
```
It opens two port-forwards (the API on 8080 and LocalStack on 4566 for the presigned upload), runs the same flow as Phase 1, and closes them. You want `"status": "done"` with detections. It fails early with a clear message if a port is busy.

Through the Ingress:
```bash
echo "$(minikube ip) visionhive.local" | sudo tee -a /etc/hosts
curl -s http://visionhive.local/health
```
If that hangs (it can with the Docker driver), run `minikube tunnel` in a second terminal and use `127.0.0.1` in the hosts line instead.

Watch the platform work:
```bash
kubectl get pods -w
kubectl logs deploy/ingest-worker -f
kubectl describe pod -l app=api-gateway | tail -30
kubectl exec deploy/localstack -- awslocal sqs list-queues
```

## 7. Autoscaling demo
```bash
kubectl get hpa
kubectl run load --rm -i --restart=Never --image=busybox:1.36 -- /bin/sh -c "while true; do wget -q -O- http://api-gateway:8080/health >/dev/null; done"
```
In another terminal run `kubectl get hpa -w` and `kubectl get pods -w`. CPU rises above 50% of the 50m request, and replicas grow from 2 toward 5. Stop the load with Ctrl+C. Scale-down takes about 5 minutes (a deliberate delay). If TARGETS shows `<unknown>`, wait a minute, or check `kubectl top pods` and that the metrics-server addon is enabled.

## 8. Break-fix labs (write each in docs/incidents/)
Every lab: break it, find the cause with `get`, `describe`, `logs`, fix it, write it up.
1. **ImagePullBackOff.** `kubectl set image deployment/api-gateway api-gateway=visionhive/api-gateway:nope`. Watch the new pods. `kubectl describe pod <name>` shows the pull error in Events. Fix: `kubectl rollout undo deployment/api-gateway`.
2. **OOMKilled.** `kubectl set resources deployment/ingest-worker --requests=memory=4Mi --limits=memory=8Mi`. The pod restarts. `kubectl describe pod -l app=ingest-worker` shows `Last State: Terminated, Reason: OOMKilled`. Fix: `kubectl rollout undo deployment/ingest-worker`.
3. **Failing readiness probe.** `kubectl patch deployment api-gateway --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/nope"}]'`. New pods stay `Running` but `0/1`. The rollout stops and the **old pods keep serving traffic**. `kubectl get endpoints api-gateway` shows who receives traffic. Fix: `kubectl rollout undo deployment/api-gateway`.
4. **Self-healing.** `kubectl delete pod -l app=api-gateway` then `kubectl get pods -w`. The ReplicaSet recreates them.
5. **Data survives.** `kubectl exec postgres-0 -- psql -U visionhive -d visionhive -c "insert into videos(id,filename,s3_key) values (gen_random_uuid(),'keep.mp4','x');"`, then `kubectl delete pod postgres-0`, wait for it, and run `select count(*) from videos;`. The row is still there because of the PVC.
6. **Service with no endpoints.** `kubectl patch svc upload-svc -p '{"spec":{"selector":{"app":"wrong"}}}'`, then `kubectl get endpoints upload-svc` (empty) and run `./scripts/k8s-test.sh` (it fails). Fix: `kubectl apply -k k8s`.
7. **Poison message in Kubernetes.** `./scripts/k8s-test.sh corrupt.mp4`, watch `kubectl logs deploy/ingest-worker`, then `kubectl exec deploy/localstack -- awslocal sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/visionhive-dlq --attribute-names ApproximateNumberOfMessages`.
8. **Rolling update.** Change `PROCESS_SECONDS` in `k8s/configmap.yaml`, run `kubectl apply -k k8s`, then `kubectl rollout restart deployment/ingest-worker` and `kubectl rollout history deployment/ingest-worker`. Note that pods only read a ConfigMap at start.

## 9. Everyday commands
| Task | Command |
|---|---|
| What is running | `kubectl get pods -o wide` |
| Why is a pod unhappy | `kubectl describe pod <name>` (read **Events** at the bottom) |
| App logs | `kubectl logs <pod>`, `kubectl logs <pod> --previous` (the crashed container), `-f` to follow |
| Shell inside a pod | `kubectl exec -it <pod> -- sh` |
| Recent cluster events | `kubectl get events --sort-by=.lastTimestamp` |
| Rollout state and undo | `kubectl rollout status deployment/<n>`, `kubectl rollout undo deployment/<n>` |
| CPU and memory use | `kubectl top pods` |
| See the final YAML | `kubectl apply -k k8s --dry-run=client -o yaml` |

## 10. Commit through a pull request
```bash
cd ~/Downloads/visionhive
git status --short
git add -A
git commit -m "feat: kubernetes manifests for minikube"
git push -u origin feature/phase7-kubernetes
gh pr create --base dev --head feature/phase7-kubernetes --title "feat: kubernetes on minikube" --body "Kustomize manifests, HPA, PDB, ingress, scripts"
gh pr checks --watch
```
There are no secrets in `k8s/` on purpose (the script creates them). Merge when green.

## 11. Verify, then clean up
```bash
./scripts/verify-phase7.sh --test
./scripts/k8s-down.sh --stop
```
`--stop` frees the laptop's memory and keeps the cluster, so `./scripts/k8s-up.sh` starts it again in a minute. Use `--delete` to remove the cluster completely. To get the Compose stack back, run `make up`.

## 12. What changes on EKS (Phases 9 to 11)
| Here (Minikube) | On EKS |
|---|---|
| Images built into Minikube, tag `local` | Images pulled from ECR with the commit tag from Phase 6 |
| LocalStack for S3 and SQS, fake keys | Real S3 and SQS, access through IRSA roles (the Phase 5 policies) |
| Postgres StatefulSet | RDS, password from Secrets Manager through External Secrets |
| `kubectl apply -k` by hand | Argo CD applies it from Git |
| Ingress with ingress-nginx | AWS Load Balancer Controller (ALB), or Gateway API |
| HPA on CPU | KEDA scaling the worker on queue depth, Karpenter adding nodes |
| One node | Several nodes across 3 zones, spot nodes for workers |

## 13. Checklist
- [ ] Minikube running with ingress and metrics-server enabled
- [ ] All pods `Running` and `Ready`, database volume `Bound`
- [ ] `./scripts/k8s-test.sh` ends with `"status": "done"`
- [ ] You reached the app through the Ingress or `minikube tunnel`
- [ ] The autoscaler added pods under load
- [ ] At least 4 labs done and written up
- [ ] Pull request merged, `./scripts/verify-phase7.sh --test` says ALL GOOD
- [ ] Cluster stopped (`k8s-down.sh --stop`)

## 14. Interview questions
- What is the difference between a Deployment and a StatefulSet?
- What happens to traffic when a readiness probe fails? And a liveness probe?
- What is the difference between requests and limits, and what is OOMKilled?
- How does a Service find its pods?
- How do you roll back a bad release?
- Why are secrets created outside Git here, and how will that work on EKS?
- Why is CPU a poor signal for scaling a queue worker?
