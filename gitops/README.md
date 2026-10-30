# GitOps

Terraform installs Argo CD and External Secrets once, from
`azure/autobutler/ci-gitops.tf`. Argo then applies whatever is under
`gitops/autobutler/apps` on `main`. Terraform does not own the runner Helm release, and
this directory is not the chart. The chart is `ghcr.io/autobutler-org/ci-runners`, and
other people can install it without this repo's state.

`gitops/autobutler/ci-runners/values.yaml` is the Azure-specific values file for that
chart. It sits outside `apps/` so the root Application, which syncs `apps/` recursively,
does not try to apply it as a manifest. The runner Application references it as a Helm
value file via a second source.

## Repository credential

`autobutler-org/iac` is public, so Argo clones it with no credential. Do not project
`argocd-repo-token` into a repository secret unless the repo becomes private. A value
that is not a GitHub token makes GitHub reject the clone, and that failure blocks the
sync of this public repo.

The GitHub App key is different. The chart consumes it after Argo is already up. The
manifest is `gitops/autobutler/pending/github-app.yaml` until the vault secret exists,
and it must not be passed to the chart with helm `--set`.

## Secrets a person sets

Terraform never holds the value. After the App exists, set its private key in
`kv-autobutler-ci`. The command is in `modules/ci-cluster/README.md`. There is no
`azurerm_key_vault_secret` for it.

## Not synced yet

`gitops/autobutler/pending/` is outside the directory Argo applies. Two manifests live
there because applying them makes the root Application Degraded:

* `ci-runners.yaml` points at chart `ci-runners` version `0.1.0` in
  `ghcr.io/autobutler-org`. That tag does not exist yet. This repo is not where the
  chart is developed.
* `github-app.yaml` reads Key Vault secret `github-app-private-key`. That secret is
  not set. The Actions GitHub App does not exist yet.

Move each file back under `gitops/autobutler/apps/` when its dependency exists. Until
then Argo only syncs the `ci-runners` namespace.

`workloadIdentityClientId` in the values file is an empty string on purpose. Fill it from
the `ci_runner_identity_client_id` output after the first apply. Do not invent a GUID,
and do not put a private key or a PAT in that file.

## Argo

The Argo server Service is a LoadBalancer on the static address from the cluster
module. `argo.errand.cloud.autobutler.org` is the A record for that address. Runners
dial out. The management UI at `errand.cloud.autobutler.org` is not this Service.
