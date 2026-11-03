# A user-assigned identity is bound to the tenant it was created in. Moving the
# subscription to another directory leaves it broken, and Microsoft's fix is delete and
# recreate. Keying this on the tenant makes that a plan: a tenant change replaces it, and
# replace_triggered_by below replaces every identity with it. The new principal and
# client ids then flow into the federated credentials, role assignments and access
# policies that reference them. No prevent_destroy on the identities: it would block
# exactly this replacement, and an identity holds no data.
resource "terraform_data" "tenant" {
  input = data.azurerm_client_config.current.tenant_id
}

# User-assigned, not the system-assigned identity Azure CLI would create and not the
# kubelet identity AKS creates later. The CLI would also attach Network Contributor.
# Terraform creates that assignment itself, in network.tf, and the cluster waits for it.
resource "azurerm_user_assigned_identity" "control" {
  name                = local.control_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

# The runner workload identity. Distinct from the kubelet identity: the kubelet identity
# pulls from the registry, and this one reads the cache and the Key Vault. The federated
# credential subject below is a contract with the chart this repo does not contain.
resource "azurerm_user_assigned_identity" "runner" {
  name                = local.runner_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

# system:serviceaccount:ci-runners:ci-runners, audience api://AzureADTokenExchange.
# The chart's service account has to use that name and namespace, or the token exchange
# fails and the runner cannot read the cache. Issuer is this cluster's OIDC issuer, so
# the credential cannot exist until the cluster does.
resource "azurerm_federated_identity_credential" "runner" {
  name                      = "ci-runners"
  user_assigned_identity_id = azurerm_user_assigned_identity.runner.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:ci-runners:ci-runners"
}

# Push identity for Quark's CI image workflow. Not the kubelet (pull only) and not
# the runner. The subject is Quark's immutable OIDC prefix, read 2026-10-30 from
# gh api repos/autobutler-org/quark/actions/oidc/customization/sub. A classic
# repo:autobutler-org/quark subject would not match and login would fail with
# AADSTS700213. workflow_dispatch and push on main both present this subject.
resource "azurerm_user_assigned_identity" "image" {
  name                = local.image_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

resource "azurerm_federated_identity_credential" "image_quark_main" {
  name                      = "quark-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.image.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:autobutler-org@217851255/quark@929272958:ref:refs/heads/main"
}
