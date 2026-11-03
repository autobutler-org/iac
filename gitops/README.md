# GitOps

Terraform installs Argo CD and External Secrets once, from
`azure/autobutler/ci-gitops.tf`. Argo then applies whatever is under
`gitops/autobutler/apps` on `main`. The runners come from the Errand chart, which lives in
[autobutler-org/errand](https://github.com/autobutler-org/errand), with our values beside `apps/`.

## Repository credential

`autobutler-org/iac` is public, so Argo clones it with no credential. Do not project
`argocd-repo-token` into a repository secret unless the repo becomes private. A value
that is not a GitHub token makes GitHub reject the clone, and that failure blocks the
sync of this public repo.

The GitHub App key is different. The chart consumes it after Argo is already up.
`gitops/autobutler/apps/github-app.yaml` projects it into a Kubernetes Secret. It must
not be passed to the chart with helm `--set`. The app is `autobutler-errand`, id
`5535744`, installation `176747827`.

## Secrets a person sets

Terraform never holds the value. After the App exists, set its private key in
`kv-autobutler-ci`. The command is in `modules/ci-cluster/README.md`. There is no
`azurerm_key_vault_secret` for it.

## Runners

`apps/errand.yaml` is one Argo Application for the Errand chart,
`oci://ghcr.io/autobutler-org/charts/errand` at 0.1.0. The chart installs the Actions Runner
Controller (`gha-runner-scale-set-controller` 0.15.1, named `errand-controller`) and one runner
scale set per entry under `runners:` in `errand/values.yaml`. The values file sits outside `apps/`
so the directory sync does not apply it as a manifest. The chart's CRDs need server-side apply.

Each entry's `label` becomes the scale set `errand-<label>`, and that is its `runs-on` label. There
are thirty-two: `<arch>[-<size>][-quark-<kind>]`, with `arm` or `x64`, an optional `small`,
`medium` or `large`, and an optional `backend`, `frontend` or `full`. Every runner starts from
`defaults` and the entry layers its own fields on top. Every set uses privileged Docker-in-Docker.

```yaml
runs-on:
  group: errand
  labels: errand-arm-quark-backend
```

| Label | Job image |
| --- | --- |
| `errand-arm`, `errand-x64` and their sizes | `ghcr.io/actions/actions-runner:2.338.2` |
| `errand-<arch>[-<size>]-quark-backend` | `autobutlerci.azurecr.io/quark/ci-backend:latest` |
| `errand-<arch>[-<size>]-quark-frontend` | `autobutlerci.azurecr.io/quark/ci-frontend:latest` |
| `errand-<arch>[-<size>]-quark-full` | `autobutlerci.azurecr.io/quark/ci-full:latest` |

Each Quark set runs its job image as the pod, with `imagePullPolicy: Always`, so a job on that
label runs in the image without naming `container:`. Every Quark image carries the Actions runner
and `/home/runner/run.sh`. The kubelet pulls it with its Container Registry Repository Reader
assignment. Before each job the ACR login hook logs Docker into `autobutlerci.azurecr.io` as well,
for a job that pulls from the registry.

The CPU and memory limit is on the pod, not on the runner container, so the runner and the dind
sidecar share it. A Docker build runs in dind, and a container limit left dind unbounded and
uncounted by the scheduler. Requests equal the limits. An unsized runner gets 3500m and 10Gi, which
is as much as a 4 vCPU, 16 GiB node leaves after AKS reserves and daemonsets: the GitHub-hosted
size, one pod per node. Each size doubles the last:

| Size | CPU limit | Memory limit |
| --- | --- | --- |
| `small` | 875m | 2.5Gi |
| `medium` | 1750m | 5Gi |
| `large` | 3500m | 10Gi |

`large` matches the unsized label. 4 cores would not schedule on these nodes.

All thirty-two sets belong to the organization runner group `errand`, not Default. Create that
group before the scale sets sync. Give it private-repository visibility and do not allow public
repositories. Privileged Docker-in-Docker on a public repository accepts jobs from fork pull
requests.

## Argo

The Argo server Service is a LoadBalancer on the static address from the cluster
module. `argo.errand.cloud.autobutler.org` is the A record for that address. Runners
dial out. The management UI at `errand.cloud.autobutler.org` is not this Service.
