# `factory` module

Infrastructure for the [factory](https://github.com/autobutler-org/factory) MVP: a
dedicated AKS cluster for the factory server and its agent workers, a PostgreSQL
flexible server with the `factory` and `substrate` databases, a Key Vault, managed
Prometheus and Grafana, a private blob container for Substrate snapshots, and
`factory.cloud.autobutler.org`.

Workers are plain Kubernetes Jobs for the MVP. Agent Substrate may be added later; the
`substrate` database, the snapshot container and Kubernetes 1.37 keep that open at no
extra cost.

External Secrets and the `factory` and `factory-workers` namespaces are installed from the root module, in
`azure/autobutler/factory-gitops.tf`. The factory chart is not. It lives in
autobutler-org/factory and is deployed from that repository's workflows.

Apply happens from `main` via CI. Do not apply this module from a laptop.

## Why a cluster of its own

Agent sessions run code nobody has reviewed. In `autobutler-ci` they would share a
control plane with Argo CD, External Secrets and the Errand GitHub App key, and a
sandbox escape would land one hop from all of them. A second cluster costs one more
`Standard_D2s_v6` node, about $74 a month. The cluster copies the shape of
`modules/ci-cluster` rather than instantiating it: that module's names are fixed
contracts, and it carries a registry, a cache and an Argo address this cluster does not
need.

## What is in it

| Piece | Size | Notes |
| --- | --- | --- |
| AKS, Free tier, Kubernetes 1.37 | | Entra-only, OIDC issuer, workload identity, Cilium overlay with ACNS FQDN policy, managed Prometheus add-on. |
| `system` pool | `Standard_D2s_v6`, 1 to 2 | Untainted. Runs AKS addons, External Secrets and the factory server. |
| `workers` pool | `Standard_D4pds_v6`, 0 to 3 | Arm, 4 cores, 16 GiB, 128 GiB ephemeral OS disk on local NVMe. Label and taint `factory.autobutler.org/workers=true`. |
| Azure Monitor workspace `amw-autobutler-factory` | | Managed Prometheus, with the default node, kubernetes and UX recording rules. |
| Azure Managed Grafana `autobutler-factory` | Standard, Grafana 12 | The workspace is its data source. |
| PostgreSQL 17 flexible server | `B_Standard_B1ms`, 32 GiB | In `eastus2`. Databases `factory` and `substrate`. 7-day backups, no HA. |
| Key Vault `kv-autobutler-factory` | standard | Access policies, like the CI vault. |
| Storage `stautobutlerfactory/substrate-snapshots` | LRS | Private, no account keys. |
| Static IPs | 2 | Ingress for `factory.cloud.autobutler.org`, and the cluster's only egress address. |

Kubernetes is 1.37. The worker design needs 1.33 or newer; 1.37 rather than the CI
cluster's 1.36 also serves the PodCertificateRequest and ClusterTrustBundle APIs
Substrate needs, which are beta and off by default on 1.36. AKS has no switch for beta
APIs or feature gates.

PostgreSQL is in `eastus2` because flexible server provisioning is restricted in
`eastus` for this subscription. It is public, and its firewall admits only the
cluster's static egress address. TLS is required.

## Quota

Checked in `eastus` on 2026-11-18 with `az vm list-usage`:

| Family | Limit | In use | This module at max |
| --- | --- | --- | --- |
| Dsv6 | 10 | 2 (CI system node) | 4, plus 2 while the pool rotates |
| Dpdsv6 | 400 | 0 (CI Arm pool can reach 8) | 12, plus 4 while the pool rotates |

Re-run `./bootstrap/github-oidc.bash create` before the first apply. Grafana's identity
gets Monitoring Data Reader on the workspace and the apply identity gets Grafana Admin,
and both roles were added to the script's condition with this module.

## After the first apply

### Get a kubeconfig

Local accounts are off, so there is no admin kubeconfig. You need Azure Kubernetes
Service Cluster User Role and an RBAC role on the cluster; grant them by hand to
yourself or to a group.

```bash
az aks get-credentials --resource-group autobutler-factory --name autobutler-factory
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
```

### Create the database roles and write the URLs

Terraform writes one secret, `postgres-admin-password`. Terraform never sees the
application passwords. A person creates them, from an address the server firewall
admits. Add a temporary firewall rule for your own address, or run `psql` in a pod in
the cluster.

Grant yourself access to the vault. The policies terraform manages are left alone:

```bash
az keyvault set-policy --name kv-autobutler-factory \
  --object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --secret-permissions get list set
```

Connect as the admin:

```bash
export PGPASSWORD="$(az keyvault secret show --vault-name kv-autobutler-factory \
  --name postgres-admin-password --query value -o tsv)"
psql "host=psql-autobutler-factory.postgres.database.azure.com user=factoryadmin dbname=factory sslmode=require"
```

Create the factory role, and make it the owner of its database:

```sql
CREATE ROLE factory LOGIN PASSWORD '<generated>';
ALTER DATABASE factory OWNER TO factory;
\c factory
ALTER SCHEMA public OWNER TO factory;
```

Only if Substrate is adopted: run its `pkg/postgressetup/setup.sql` against the `substrate`
database, following its
[database guide](https://github.com/agent-substrate/substrate/blob/main/docs/guides/postgres.md#operator-provisioned-byo-db),
with passwords for the owner and read/write logins.

Then write the URLs. `sslmode=require` is needed; the server refuses plain connections:

```bash
az keyvault secret set --vault-name kv-autobutler-factory --name factory-database-url \
  --value 'postgres://factory:<password>@psql-autobutler-factory.postgres.database.azure.com:5432/factory?sslmode=require'
az keyvault secret set --vault-name kv-autobutler-factory --name substrate-owner-database-url \
  --value 'postgres://substrate_owner_user:<password>@psql-autobutler-factory.postgres.database.azure.com:5432/substrate?sslmode=require'
az keyvault secret set --vault-name kv-autobutler-factory --name substrate-readwrite-database-url \
  --value 'postgres://substrate_readwrite_user:<password>@psql-autobutler-factory.postgres.database.azure.com:5432/substrate?sslmode=require'
```

`factory-database-url` reaches the cluster as the Secret `factory-database`, key `url`,
in the `factory` namespace, within an hour or on
`kubectl -n factory annotate externalsecret factory-database force-sync=$(date +%s) --overwrite`.
The two Substrate URLs, written only if Substrate is adopted, are read at install time:
`ATE_API_POSTGRES_OWNER_CONNECTION_STRING` and
`ATE_API_POSTGRES_READ_WRITE_CONNECTION_STRING`.

## What the factory chart consumes

| Thing | Value |
| --- | --- |
| Namespaces | `factory` for the server; `factory-workers` for Jobs, Pod Security `restricted`, ResourceQuota `workers` |
| Database URL | Secret `factory-database`, key `url`, in `factory` |
| Secret store | ClusterSecretStore `autobutler-factory`, for any further ExternalSecret |
| Hostname | `factory.cloud.autobutler.org` |
| Ingress address | Service `type: LoadBalancer` with annotations `service.beta.kubernetes.io/azure-load-balancer-resource-group: autobutler-factory` and `service.beta.kubernetes.io/azure-pip-name: autobutler-factory-ingress-pip` |
| Worker nodes | nodeSelector `factory.autobutler.org/workers: "true"`, toleration for `factory.autobutler.org/workers=true:NoSchedule`, `kubernetes.io/arch: arm64` |
| Worker disk | 128 GiB ephemeral OS disk per node, shared by every worker pod on it |
| Egress policy | `CiliumNetworkPolicy` with `toFQDNs`, from ACNS; the chart owns the policies |
| Token issuer | `factory_oidc_issuer_url` output, for verifying projected ServiceAccount tokens |
| Scraping | a `ServiceMonitor` or `PodMonitor` in `azmonitoring.coreos.com/v1`, not `monitoring.coreos.com` |
| Grafana | `factory_grafana_url` output |
| PromQL | `factory_monitor_workspace_query_endpoint` output |
| Snapshot container | `https://stautobutlerfactory.blob.core.windows.net/substrate-snapshots`, only if Substrate is adopted |
| Deploy identity | `factory_deploy_identity_client_id` output |

There is no `gvisor` RuntimeClass. AKS does not offer gVisor; its native sandbox runtime
is Kata (`KataVmIsolation` on Azure Linux, x64 sizes with nested virtualization), which
would mean an x64 workers pool. Installing runsc by DaemonSet onto AKS nodes is not
supported and is not a small change.

## Metrics, dashboards and alerts

The ama-metrics add-on scrapes the cluster and ships to the workspace with no
Prometheus in the cluster. To scrape the factory server, the chart adds a
`ServiceMonitor` (or `PodMonitor`) with `apiVersion: azmonitoring.coreos.com/v1`; the
add-on ships those CRDs and watches every namespace. The usual `monitoring.coreos.com`
kind is ignored.

Alert rules are terraform: `azurerm_monitor_alert_prometheus_rule_group` resources in
`monitor.tf`, beside the recording rules, with an action group when there is somewhere
to send them. Dashboards are JSON in autobutler-org/factory, imported with the
`grafana` terraform provider authenticated as the apply identity, which holds Grafana
Admin. Managed Grafana has no provisioning directory to mount.

Container logs (Container Insights) are not enabled. It needs a Log Analytics workspace
and its own data collection rule, and ingestion is billed per GB of whatever agent
builds print. `kubectl logs` covers the MVP.

TLS follows the rest of this repo: the service gets its own certificate with ACME, as
Caddy does on the quark instance, rather than this cluster running an ingress
controller and cert-manager for one hostname.

Substrate's object store plugin speaks `gs://` and `s3://`, not Azure Blob. Substrate
reaches the snapshot container through an S3-compatible gateway chosen with the
Substrate install. That gateway's identity and its Storage Blob Data Contributor grant
on the account come with it.

## Deploying from autobutler-org/factory

`id-autobutler-factory-deploy` federates with
`repo:autobutler-org@217851255/factory@1463156387:ref:refs/heads/main`, the factory
repository's immutable subject on `main`. It has Cluster User and RBAC Cluster Admin on
this cluster, nothing else. A workflow on `main` with `id-token: write` deploys with:

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ vars.FACTORY_DEPLOY_AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
- run: |
    az aks get-credentials --resource-group autobutler-factory --name autobutler-factory
    kubelogin convert-kubeconfig -l azurecli
    helm upgrade --install factory ./deploy/chart --namespace factory
```

None of the three values is a secret. A pull request cannot match the subject, so
it cannot deploy.
