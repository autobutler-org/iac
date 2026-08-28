# Bootstrap

Two setup steps that have to happen before Terraform can do anything:

1. **`main.bicep`** — the Azure Storage account every root module keeps its state in.
2. **`github-oidc.bash`** — the Entra ID identity GitHub Actions authenticates as.

Both are one-time, and both are idempotent.

## Why this is Bicep and not Terraform

Chicken and egg. A Terraform backend has to exist before Terraform has anywhere to record
what it built, so whatever creates the backend cannot itself be a Terraform stack with a
remote backend. The alternatives are a local state file that someone has to keep safe
forever, or a bootstrap stack that manages itself and can lock itself out. An ARM
deployment sidesteps both: `az deployment sub create` is idempotent and keeps its own
history in the subscription, so there is no state file to lose.

## What it creates

In the `autobutler` subscription:

| Resource | Name | Notes |
| --- | --- | --- |
| Resource group | `autobutler-tfstate` | |
| Storage account | `stautobutlertfstate` | `Standard_GRS`, TLS 1.2, no public blob access |
| Blob container | `tfstate` | private; one `.tfstate` blob per stack |
| Role assignment | Storage Blob Data Owner | for `principalId` in `main.bicepparam` |
| Management lock | `no-accidental-deletion` | `CanNotDelete` on the storage account |

Two settings are load-bearing:

- **`allowSharedKeyAccess: false`** — there are no account keys, so every caller
  authenticates as an Entra ID principal. This is why each stack's `backend.tf` sets
  `use_azuread_auth = true` and omits `resource_group_name`; that argument exists only to
  drive the account-key lookup this setting makes impossible.
- **Blob versioning, plus 30-day blob and container soft delete** — the recovery story
  below depends on both.

State locking is a native blob lease. There is no lock table to provision.

## Step 1: deploy the state backend

```bash
make bootstrap/whatif   # preview
make bootstrap          # deploy
```

Both are idempotent; re-running after a parameter change updates in place.

Grant a second person access by changing `principalId` in `main.bicepparam` and
redeploying, or directly:

```bash
az role assignment create \
  --role "Storage Blob Data Owner" \
  --assignee <object-id> \
  --scope "$(az storage account show -n stautobutlertfstate -g autobutler-tfstate --query id -o tsv)"
```

## Step 2: create the CI identity

`.github/workflows/plan.yml` and `apply.yml` authenticate to Azure with OIDC — GitHub mints
a short-lived token that Azure trusts, so there is no client secret to store or rotate. That
needs an Entra ID app registration with federated credentials, which Bicep cannot create:
app registrations are Microsoft Graph, not ARM.

```bash
./bootstrap/github-oidc.bash --help     # what it will do
./bootstrap/github-oidc.bash create
./bootstrap/github-oidc.bash doctor     # what exists now, and what is missing
```

Run it after step 1 — it grants the CI principal Storage Blob Data Contributor on the state
account, and skips that grant with a warning if the account does not exist yet.

It creates the app registration and service principal, three federated credentials (one per
subject the workflows mint: `pull_request`, `ref:refs/heads/main`, and
`environment:production`), a Contributor role assignment on the subscription, and the state
account grant. It finishes by printing the `gh variable set` commands for
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`.

Those three are repository **variables**, not secrets. None of them is sensitive, and with
OIDC there is no client secret at all — which is the point.

Re-run `create` freely; every step checks for what it would create first.

## Wiring up a new stack

The backend block for a stack at `azure/<subscription>/<stack>/`:

```hcl
backend "azurerm" {
  storage_account_name = "stautobutlertfstate"
  container_name       = "tfstate"
  key                  = "azure/<subscription>/<stack>.tfstate"
  use_azuread_auth     = true
  subscription_id      = "8add0a4f-6638-4cf3-95bd-cd46ab3ca970"
  tenant_id            = "1196631e-40d1-42f3-91a4-1c80f49065f8"
}
```

`subscription_id` here is the subscription holding the *state account*, not the one the
stack deploys into. It is pinned so state stays common to the whole estate even when a
stack targets a different subscription. The target subscription comes from
`ARM_SUBSCRIPTION_ID`, which the Makefile derives from the directory name.

Give each root module its own `key`. Two sharing a key will overwrite each other.

If you add a new GitHub environment or branch that CI runs from, add a matching federated
credential — `./bootstrap/github-oidc.bash create --environment <name>` — or the OIDC
exchange fails with an error that reads like a permissions problem rather than a missing
subject.

## Recovering a clobbered state file

Versioning keeps every prior state blob, so a bad apply is recoverable without hunting for
someone's local copy.

```bash
STACK_KEY=azure/autobutler/quark-release.tfstate

# List versions, newest first.
az storage blob list \
  --account-name stautobutlertfstate --container-name tfstate \
  --prefix "$STACK_KEY" --include v --auth-mode login \
  --query "[].{name:name, version:versionId, modified:properties.lastModified}" -o table

# Download one to inspect before committing to it.
az storage blob download \
  --account-name stautobutlertfstate --container-name tfstate \
  --name "$STACK_KEY" --version-id <version-id> \
  --file recovered.tfstate --auth-mode login

# Promote it back to current.
az storage blob copy start \
  --account-name stautobutlertfstate --destination-container tfstate \
  --destination-blob "$STACK_KEY" \
  --source-uri "https://stautobutlertfstate.blob.core.windows.net/tfstate/${STACK_KEY}?versionId=<version-id>" \
  --auth-mode login
```

If a `terraform apply` died mid-flight it may have left a stale lease on the blob. Break it
with `terraform force-unlock <lock-id>` — the Storage Blob Data Owner role grants the
lease-break permission that makes this work.

## Deleting the account

The `CanNotDelete` lock has to come off by hand first. It exists because deleting this one
account destroys every stack's state at once, and no amount of blob versioning survives the
account going away.

```bash
az lock delete --name no-accidental-deletion \
  --resource-group autobutler-tfstate --resource-name stautobutlertfstate \
  --namespace Microsoft.Storage --resource-type storageAccounts
```
