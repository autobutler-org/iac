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
| `quark-arm-backend` | `errand/arm/quark/backend.yaml` | `quark-arm-backend` | `quark/ci-backend` |
| `quark-arm-frontend` | `errand/arm/quark/frontend.yaml` | `quark-arm-frontend` | `quark/ci-frontend` |
| `quark-arm-full` | `errand/arm/quark/full.yaml` | `quark-arm-full` | `quark/ci-full` |
| `x64` | `errand/x64/x64.yaml` | `x64` | GitHub runner |
| `quark-x64-backend` | `errand/x64/quark/backend.yaml` | `quark-x64-backend` | `quark/ci-backend` |
| `quark-x64-frontend` | `errand/x64/quark/frontend.yaml` | `quark-x64-frontend` | `quark/ci-frontend` |
| `quark-x64-full` | `errand/x64/quark/full.yaml` | `quark-x64-full` | `quark/ci-full` |

One Application is one Helm release, and one release registers one label.
`runnerScaleSetName` is that label. Listing several paths under `valueFiles`
merges them into the one release. The value files sit outside `apps/` so the
directory sync does not apply them as manifests. Each set pins
`controllerServiceAccount` to `errand-controller-gha-rs-controller` in
`ci-runners`. Argo renders with `helm template`, whose lookup cannot see the
controller Deployment, and chart 0.15.1 fails closed unless both the name and
the namespace are set. Every set uses privileged Docker-in-Docker.

The pod image is `ghcr.io/actions/actions-runner:2.338.2` on every set. That
image contains `/home/runner/run.sh`. `ci-backend` and `ci-frontend` do not, so
they cannot be the pod. The kubelet pulls the pod image before the ACR login
hook. Before each job the runner logs into `autobutlerci.azurecr.io`, and
Docker then pulls the image named by `container:`.

```yaml
runs-on:
  group: errand
  labels: quark-arm-backend
container:
  image: autobutlerci.azurecr.io/quark/ci-backend:latest
```

`quark-arm-frontend` uses `quark/ci-frontend`, and `quark-arm-full` uses
`quark/ci-full`. The x64 labels are `quark-x64-backend`, `quark-x64-frontend`,
and `quark-x64-full`. `arm` and `x64` are the GitHub runner image, with no
required `container:`. The Application for each set lives under
`gitops/autobutler/apps/errand/`, in the same `arm/` and `x64/` layout as the
values. All eight sets belong to the organization runner group `errand`, not Default. Create that group before the
scale sets sync. Give it private-repository visibility and do not allow public
repositories. Privileged Docker-in-Docker on a public repository accepts jobs
from fork pull requests.

## Argo

The Argo server Service is a LoadBalancer on the static address from the cluster
module. `argo.errand.cloud.autobutler.org` is the A record for that address. Runners
dial out. The management UI at `errand.cloud.autobutler.org` is not this Service.
