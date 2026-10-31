# GitOps

Terraform installs Argo CD and External Secrets once, from
`azure/autobutler/ci-gitops.tf`. Argo then applies whatever is under
`gitops/autobutler/apps` on `main`. There is no Errand chart in this repo or in
another one. The runner scale sets are GitHub's charts, with our values beside `apps/`.

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

There is no Errand chart. Argo installs GitHub's charts from
`ghcr.io/actions/actions-runner-controller-charts` at version 0.15.1.

| Application | Values | `runs-on` label | Job image |
| --- | --- | --- | --- |
| `errand-controller` | | | |
| `arm` | `errand/arm/arm.yaml` | `arm` | GitHub runner |
| `arm-quark-backend` | `errand/arm/quark/backend.yaml` | `arm-quark-backend` | `quark/ci-backend` |
| `arm-quark-frontend` | `errand/arm/quark/frontend.yaml` | `arm-quark-frontend` | `quark/ci-frontend` |
| `arm-quark-full` | `errand/arm/quark/full.yaml` | `arm-quark-full` | `quark/ci-full` |
| `x64` | `errand/x64/x64.yaml` | `x64` | GitHub runner |
| `x64-quark-backend` | `errand/x64/quark/backend.yaml` | `x64-quark-backend` | `quark/ci-backend` |
| `x64-quark-frontend` | `errand/x64/quark/frontend.yaml` | `x64-quark-frontend` | `quark/ci-frontend` |
| `x64-quark-full` | `errand/x64/quark/full.yaml` | `x64-quark-full` | `quark/ci-full` |

One Application is one Helm release, and one release registers one label.
`runnerScaleSetName` is that label. Listing several paths under `valueFiles`
merges them into the one release. The value files sit outside `apps/` so the
directory sync does not apply them as manifests. Each set pins
`controllerServiceAccount` to `errand-controller-gha-rs-controller` in
`ci-runners`. Argo renders with `helm template`, whose lookup cannot see the
controller Deployment, and chart 0.15.1 fails closed unless both the name and
the namespace are set. Every set uses privileged Docker-in-Docker.

`arm` and `x64` run `ghcr.io/actions/actions-runner:2.338.2`. Each Quark set
runs its job image as the pod, `autobutlerci.azurecr.io/quark/ci-<kind>:latest`
with `imagePullPolicy: Always`, so a job on that label runs in the image without
naming `container:`. Every Quark image carries the Actions runner and
`/home/runner/run.sh`. The kubelet pulls it with its Container Registry
Repository Reader assignment. Before each job the ACR login hook logs Docker
into `autobutlerci.azurecr.io` as well, for a job that pulls from the registry.

Every runner pod has a limit of 3500m CPU and 10Gi memory, which is as much as a
4 vCPU, 16 GiB node leaves after AKS reserves and daemonsets. That is the
GitHub-hosted size. Requests default to the limit, so it is one pod per node.

Each label also has `small`, `medium` and `large` variants. The size goes after
the architecture and before the app: `arm-small`, `x64-medium-quark-backend`,
`arm-large-quark-full`. Each is its own scale set, with values under
`errand/<arch>/<size>/` and its Application under `apps/errand/<arch>/<size>/`.
Each size doubles the last, and the unsized label keeps the full limit:

| Size | CPU limit | Memory limit |
| --- | --- | --- |
| `small` | 875m | 2.5Gi |
| `medium` | 1750m | 5Gi |
| `large` | 3500m | 10Gi |

`large` matches the unsized label. 4 cores would not schedule on these nodes.

```yaml
runs-on:
  group: errand
  labels: arm-quark-backend
```

`arm-quark-frontend` runs `quark/ci-frontend`, and `arm-quark-full` runs
`quark/ci-full`. The x64 labels are `x64-quark-backend`, `x64-quark-frontend`,
and `x64-quark-full`. The Application for each set lives under
`gitops/autobutler/apps/errand/`, in the same `arm/` and `x64/` layout as the
values. All thirty-two sets belong to the organization runner group `errand`, not Default. Create that group before the
scale sets sync. Give it private-repository visibility and do not allow public
repositories. Privileged Docker-in-Docker on a public repository accepts jobs
from fork pull requests.

## Argo

The Argo server Service is a LoadBalancer on the static address from the cluster
module. `argo.errand.cloud.autobutler.org` is the A record for that address. Runners
dial out. The management UI at `errand.cloud.autobutler.org` is not this Service.
