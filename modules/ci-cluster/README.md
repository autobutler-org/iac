# `ci-cluster` module

AutoButler's own CI cluster. Terraform owns the AKS cluster, the container registry, the
blob cache, two user-assigned identities, and a Key Vault. The runner Helm chart is not
in this repo. Other people install that chart without this repo's state, and Argo CD is
what applies it. This module does not install Argo.

The cluster is the Free tier. The research cost table used AKS Standard for a ten-node
always-on sketch. The first install scales the runner pool to zero, so it does not need
the uptime SLA. One `Standard_D2s_v5` system node stays up. It does not run jobs. The
runner pool is tainted `ci.autobutler.org/runner=true:NoSchedule` and scales from 0 to 3
`Standard_D4ds_v6` nodes.

Local accounts are off. The API server is public and has no authorized IP ranges, because
GitHub-hosted Actions runners have no stable egress and the Helm provider has to reach
the API from those runners. Entra is the lock.

Apply happens from `main` via CI. Do not apply this module from a laptop.

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

Nothing on this cluster accepts inbound connections. Runners dial out to GitHub. The
registry answers on `autobutlerci.azurecr.io` and the cache on
`stautobutlercicache.blob.core.windows.net`, which are Azure hostnames this module does
not have to publish. `cloud.autobutler.org` is already delegated and is where a name
would go if we later publish something from the cluster. This module does not create a
record, a dangling A record, or a public IP "for later". The cluster's `dns_prefix` is
only the Azure-managed API hostname.
