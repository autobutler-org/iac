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

| Application | Chart | `runs-on` |
| --- | --- | --- |
| `errand-controller` | `gha-runner-scale-set-controller` | |
| `errand` | `gha-runner-scale-set` | `errand` |
| `errand-x64` | `gha-runner-scale-set` | `errand-x64` |

The value files are `gitops/autobutler/errand/arm.yaml` and `x64.yaml`. They sit
outside `apps/` so the directory sync does not apply them as manifests. Both set
`controllerServiceAccount` to `errand-controller-gha-rs-controller` in `ci-runners`.
Argo renders with `helm template`, whose lookup cannot see the controller
Deployment, and chart 0.15.1 fails closed unless both the name and the namespace
are set. Both sets use privileged Docker-in-Docker. The runner image is
`autobutlerci.azurecr.io/quark/ci-full:latest` with `imagePullPolicy: Always`,
so a job with no `container:` runs in that image. Before each job the runner
logs into `autobutlerci.azurecr.io`, which lets a workflow opt into a smaller
image:

```yaml
container:
  image: autobutlerci.azurecr.io/quark/ci-backend:latest
```

The other scoped image is `quark/ci-frontend`. Both sets belong to the
organization runner group `errand`, not Default. A job names the group and the
label:

```yaml
runs-on:
  group: errand
  labels: errand
```

Use `labels: errand-x64` for the x64 set. Create the group in the organization
before the scale sets sync. Give it private-repository visibility and do not
allow public repositories. Privileged Docker-in-Docker on a public repository
accepts jobs from fork pull requests.

## Argo

The Argo server Service is a LoadBalancer on the static address from the cluster
module. `argo.errand.cloud.autobutler.org` is the A record for that address. Runners
dial out. The management UI at `errand.cloud.autobutler.org` is not this Service.
