# Replaced on a tenant change, for the reason in modules/ci-cluster/identity.tf.
resource "terraform_data" "tenant" {
  input = data.azurerm_client_config.current.tenant_id
}

resource "azurerm_user_assigned_identity" "control" {
  name                = local.control_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

# What autobutler-org/factory's deploy workflow (.github/workflows/deploy.yml) logs in as
# to upgrade the chart. It trusts only jobs in that repository's `production` GitHub
# environment, so a pull request, a fork or a workflow outside that environment cannot
# reach the cluster, and a protection rule on the environment gates every deploy. The
# subject is the repository's immutable prefix, like the quark image identity in
# modules/ci-cluster.
resource "azurerm_user_assigned_identity" "deploy" {
  name                = local.deploy_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

resource "azurerm_federated_identity_credential" "deploy_factory_production" {
  name                      = "factory-production"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.factory_repo_subject}:environment:production"
}
