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

| Application | Chart | `runs-on` label | Job image |
| --- | --- | --- | --- |
| `errand-controller` | `gha-runner-scale-set-controller` | | |
| `errand-arm` | `gha-runner-scale-set` | `errand-arm` | any, or none |
| `errand-arm-backend` | `gha-runner-scale-set` | `errand-arm-backend` | `quark/ci-backend` |
| `errand-arm-frontend` | `gha-runner-scale-set` | `errand-arm-frontend` | `quark/ci-frontend` |
| `errand-arm-full` | `gha-runner-scale-set` | `errand-arm-full` | `quark/ci-full` |
| `errand-x64` | `gha-runner-scale-set` | `errand-x64` | any, or none |
| `errand-x64-backend` | `gha-runner-scale-set` | `errand-x64-backend` | `quark/ci-backend` |
| `errand-x64-frontend` | `gha-runner-scale-set` | `errand-x64-frontend` | `quark/ci-frontend` |
| `errand-x64-full` | `gha-runner-scale-set` | `errand-x64-full` | `quark/ci-full` |

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
  labels: errand-arm-backend
container:
  image: autobutlerci.azurecr.io/quark/ci-backend:latest
```

`errand-arm-frontend` uses `quark/ci-frontend`, and `errand-arm-full` uses
`quark/ci-full`. The x64 labels are the same three images on `errand-x64-backend`,
`errand-x64-frontend`, and `errand-x64-full`. All eight sets belong to the
organization runner group `errand`, not Default. Create that group before the
scale sets sync. Give it private-repository visibility and do not allow public
repositories. Privileged Docker-in-Docker on a public repository accepts jobs
from fork pull requests.

## Argo

The Argo server Service is a LoadBalancer on the static address from the cluster
module. `argo.errand.cloud.autobutler.org` is the A record for that address. Runners
dial out. The management UI at `errand.cloud.autobutler.org` is not this Service.
