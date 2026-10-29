# AutoButler's own CI cluster: AKS, a registry, a blob cache, two user-assigned identities,
# and a Key Vault. The runner Helm chart is not in this module. Other people install that
# chart without this repo's state.
#
# A shared module has no backend, so unlike a root module (where the terraform block lives
# in backend.tf) this module's terraform block lives in main.tf. The constraints are floors,
# not pins. The root module in azure/<subscription>/ is where versions actually get set.
terraform {
  required_version = ">= 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0"
    }
  }
}

# Tenant id for the vault and for AKS Entra integration. This is the identity running
# terraform, which is fine for a tenant id and is the wrong principal to grant cluster
# admin. The GitHub Actions grant looks the service principal up by name instead. See
# cluster.tf.
data "azurerm_client_config" "current" {}

locals {
  # Names confirmed free on 2026-10-29. They are fixed because the federated-credential
  # subject, the cache URL, and the vault name are contracts with things that do not
  # live in this module.
  cluster_name          = "autobutler-ci"
  dns_prefix            = "autobutler-ci"
  registry_name         = "autobutlerci"
  storage_account_name  = "stautobutlercicache"
  cache_container_name  = "cache"
  key_vault_name        = "kv-autobutler-ci"
  control_identity_name = "id-autobutler-ci-control"
  runner_identity_name  = "id-autobutler-ci-runner"
  vnet_name             = "autobutler-ci-vnet"
  subnet_name           = "nodes"

  # Latest 1.36 patch in eastus on 2026-10-29, from `az aks get-versions -l eastus`.
  # 1.36 is Azure's default minor there. 1.37 is published and is not what this cluster
  # installs. automatic_upgrade_channel "patch" can move the control plane along later
  # 1.36 patches in Azure. The provider only suppresses a version diff for a major.minor
  # alias, so this full patch pin will show a change after one of those moves, until
  # someone bumps it. That is the pairing we want: the minor stays chosen here, and a
  # patch move is visible rather than silent. Re-check the patch if location leaves eastus.
  kubernetes_version = "1.36.4"

  # App registration bootstrap/github-oidc.bash creates. The object id we grant is the
  # service principal, looked up in cluster.tf, not the caller's.
  github_actions_app_name = "github-actions-iac"
}
