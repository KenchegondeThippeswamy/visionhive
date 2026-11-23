# gitops/

Everything Argo CD reads. Git is the single source of truth: change a file here and the cluster follows.

| Path | What it is |
|---|---|
| `argocd/values.yaml` | Helm values for installing Argo CD itself |
| `bootstrap/project.yaml` | The AppProject: which repo and namespace the apps may use, no cluster-wide objects |
| `bootstrap/root-app.yaml` | The app of apps, applied once by hand |
| `apps/` | The Applications that the root app deploys (one file per environment) |
| `local/values.yaml` | The image tag, the only thing that changes on every release |
| `local/aws.values.yaml` | Mode B: real AWS services instead of LocalStack and the in-cluster database |
| `examples/` | The mode B Application. Move it to `apps/` to use it |

Releasing: build the images, write the tag into `local/values.yaml`, commit, push to `dev`. Argo CD rolls the pods.
Rolling back: `git revert` the commit.
