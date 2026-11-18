# The factory MVP: a dedicated AKS cluster for the factory server and its agent
# workers, a PostgreSQL flexible server with the factory and substrate databases, a Key
# Vault, managed Prometheus and Grafana, a Substrate snapshot container, and the
# factory hostname.
#
# A sibling of modules/ci-cluster, not another instance of it. That module's names are
# fixed contracts, and it carries a registry, a cache, an image identity and an Argo
# address this cluster does not need. Making each optional would put a count on every
# resource of a live cluster. The cluster here copies its shape instead.
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
    # Ephemeral random_password: the PostgreSQL admin password is generated during the
    # apply and written only to write-only arguments, so it is never in state or a plan.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}

# Tenant id for the vault and for AKS Entra integration. Not the principal granted
# cluster admin: that is the github-actions-iac service principal, looked up by name.
data "azurerm_client_config" "current" {}

data "azuread_service_principal" "github_actions" {
  display_name = local.github_actions_app_name
}

locals {
  # Names confirmed free on 2026-11-18. The vault name, the hostname and the
  # federated-credential subjects are contracts with the factory chart and the factory
  # repository's workflows.
  cluster_name           = "autobutler-factory"
  dns_prefix             = "autobutler-factory"
  vnet_name              = "autobutler-factory-vnet"
  subnet_name            = "nodes"
  control_identity_name  = "id-autobutler-factory-control"
  deploy_identity_name   = "id-autobutler-factory-deploy"
  ingress_public_ip_name = "autobutler-factory-ingress-pip"
  egress_public_ip_name  = "autobutler-factory-egress-pip"
  dns_record_name        = "factory"
  key_vault_name         = "kv-autobutler-factory"
  storage_account_name   = "stautobutlerfactory"
  snapshot_container     = "substrate-snapshots"
  postgres_server_name   = "psql-autobutler-factory"
  postgres_admin_login   = "factoryadmin"
  postgres_databases     = toset(["factory", "substrate"])
  monitor_workspace_name = "amw-autobutler-factory"
  grafana_name           = "autobutler-factory"

  # The worker design needs 1.33 or newer. 1.37, not the 1.36 the CI cluster runs, keeps
  # Agent Substrate possible without an upgrade: its podcertificate-controller needs
  # the PodCertificateRequest and ClusterTrustBundle APIs. On 1.36 they are beta and off
  # by default, and AKS has no switch to serve a beta API. Substrate's docs say they
  # are served by default from 1.37. Latest 1.37 patch in eastus on 2026-11-18, from
  # `az aks get-versions -l eastus`, not preview.
  kubernetes_version = "1.37.1"

  # Immutable subject prefix of autobutler-org/factory, read 2026-11-18 from
  # gh api repos/autobutler-org/factory/actions/oidc/customization/sub.
  factory_repo_subject = "repo:autobutler-org@217851255/factory@1463156387"

  github_actions_app_name = "github-actions-iac"
}
