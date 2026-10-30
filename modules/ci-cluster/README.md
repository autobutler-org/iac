# `ci-cluster` module

AutoButler's own CI cluster. Terraform owns the AKS cluster, the container registry, the
blob cache, two user-assigned identities, and a Key Vault. The runner Helm chart is not
in this repo. Other people install that chart without this repo's state. This module
does not install the chart. Argo CD, installed from the root module, does.

The cluster is the Free tier. The research cost table used AKS Standard for a ten-node
always-on sketch. This install does not need that uptime SLA. One `Standard_D2s_v6`
system node stays up. It does not run jobs. DSv5 was the first choice for that node and
the quota for it cannot be raised in this subscription.

Runner nodes are 4 cores and 16 GiB, and both OS disks are ephemeral on NVMe. The
Arm pool (`Standard_D4pds_v6`) starts at 2 nodes and the autoscaler may grow it to
100. Two nodes are 8 vCPUs, which fits the current Dpdsv6 quota of 10. A third node
does not. The x64 pool (`Standard_F4ads_v7`) starts at 0 and may grow to 100. Fadsv7
quota is 10 as well. 100 is the concurrency target, not a count we provision now.
Both pools are tainted `ci.autobutler.org/runner=true:NoSchedule`. A runner pod
selects `kubernetes.io/arch` and `ci.autobutler.org/runner`. The system pool is
tainted `CriticalAddonsOnly=true:NoSchedule`. Argo CD and External Secrets tolerate
that taint. Other pods do not.

Local accounts are off. The API server is public and has no authorized IP ranges, because
GitHub-hosted Actions runners have no stable egress and the Helm provider has to reach
the API from those runners. Entra is the lock.

Apply happens from `main` via CI. Do not apply this module from a laptop.

## GitOps

Terraform installs Argo CD and External Secrets once, in
`azure/autobutler/ci-gitops.tf`. Argo watches `gitops/autobutler/apps` on main and is the
thing that applies the runner chart. `gitops/README.md` covers that split, the two Key
Vault secrets a person sets by hand, and why the repository credential is not a file in
the watched directory.

## Outputs

The root module re-exports these with a `ci_` prefix. `cluster_host` and
`cluster_ca_certificate` stay on the module. They are sensitive because the provider
marks the underlying attributes sensitive, and they are connection info for a Helm
provider, not client credentials. `client_certificate` and `client_key` are not outputs.
With local accounts disabled there is no admin kubeconfig to hand out.

| Output | What a consumer does with it |
| --- | --- |
| `cluster_name` | The AKS name kubectl and Argo target. |
| `cluster_id` | Scope for CI's cluster role assignments. Not the subscription. |
| `resource_group_name` | Where the cluster, registry, cache, identities, and vault live. |
| `oidc_issuer_url` | Issuer on a workload-identity federated credential. |
| `acr_login_server` | Registry the runner chart pulls from. Pull only. |
| `cache_container_url` | Private cache URL. The runner identity authenticates. |
| `key_vault_name` | Vault a person writes the GitHub App key into, by hand. |
| `key_vault_id` | Where a later access policy attaches. No secret is created here. |
| `runner_identity_client_id` | Client id the chart's Helm values take. Not a secret. |
| `runner_identity_principal_id` | Object id on the cache role and the vault policy. |
| `control_plane_identity_principal_id` | Object id that holds Network Contributor on the VNet. |
| `cluster_host` | Kubernetes API host for the Helm provider. |
| `cluster_ca_certificate` | Cluster CA for that same provider. Not a client key. |

## Before the first apply

Someone who can assign roles has to re-run `./bootstrap/github-oidc.bash create` before
the apply will succeed. The GitHub Actions identity is a Contributor. Contributor cannot
write role assignments, and this module's first role assignment fails until the script
has granted Role Based Access Control Administrator on the subscription, with a condition
that allows write and delete only for the five built-in roles this module assigns.

An unconstrained grant of that role is not the thing the script is supposed to leave
behind. `./bootstrap/github-oidc.bash doctor` reports the assignment missing when it is
absent and when it is present with an empty condition.

Do not run the script from CI, and do not run the apply locally.

## The GitHub App private key

Terraform never holds the secret. After the first apply, a person sets one Key Vault
secret. The App does not exist yet. Create it in GitHub (one Actions app, not a second
app, and not the schmeide app) and put its whole PEM here. The schmeide vault has a
secret of the same name. That is a different key. Do not copy it.

Grant yourself secret access. The runner's access policy is managed by terraform, and a
policy added by hand is left alone:

```bash
az keyvault set-policy --name kv-autobutler-ci \
  --object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --secret-permissions get list set
```

Then set the secret. `--file` keeps the PEM's line breaks, which `--value` will not:

```bash
az keyvault secret set --vault-name kv-autobutler-ci \
  --name github-app-private-key \
  --file ./github-app.private-key.pem
```

The chart reads a Kubernetes secret named `github-app-private-key`. It must not receive
the key via helm `--set`. Projecting the vault secret into the cluster is a later
change. This module creates no `azurerm_key_vault_secret`.

## Federated credential

The runner identity has one federated credential:

| | |
| --- | --- |
| Subject | `system:serviceaccount:ci-runners:ci-runners` |
| Audience | `api://AzureADTokenExchange` |
| Issuer | the cluster's OIDC issuer URL |

That subject is a contract with the chart this repo does not contain. The chart's
service account has to be named `ci-runners` in the namespace `ci-runners`, or the token
exchange fails and the runner cannot read the cache. The client id to put in the chart's
values is `runner_identity_client_id`. Fill it in after the first apply. Do not invent one.

## DNS

`argo.errand.cloud.autobutler.org` is an alias A record for a static public IP in the
cluster resource group. The Argo Service attaches that address by name. The management
UI name, `errand.cloud.autobutler.org`, is not created here. That UI does not exist yet.

Runners still dial out to GitHub. The registry answers on `autobutlerci.azurecr.io` and
the cache on `stautobutlercicache.blob.core.windows.net`. The cluster's `dns_prefix` is
only the Azure-managed API hostname.

`id-autobutler-ci-image` is the only identity that can push to that registry. Quark's
CI image workflow federates to it on main. The client id is `image_identity_client_id`.
The kubelet can pull. The runner identity cannot push.
