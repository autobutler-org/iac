# User-assigned, not the system-assigned identity Azure CLI would create and not the
# kubelet identity AKS creates later. The CLI would also attach Network Contributor.
# Terraform creates that assignment itself, in network.tf, and the cluster waits for it.
resource "azurerm_user_assigned_identity" "control" {
  name                = local.control_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
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
    prevent_destroy = true
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
