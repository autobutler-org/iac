# Azure Managed Grafana, Standard: about $25 a month for the instance ($0.0342/h in
# eastus) plus $6 per active user. Standard is the only SKU azurerm 5.13 accepts; the
# cheaper Essential tier is rejected by the provider. Zone redundancy stays off. Alert
# rules live in Azure Monitor (monitor.tf), not in Grafana.
resource "azurerm_dashboard_grafana" "this" {
  name                  = local.grafana_name
  resource_group_name   = var.resource_group_name
  location              = var.location
  sku                   = "Standard"
  grafana_major_version = 12

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }

  tags = var.tags
}

# Grafana's identity reads the workspace. Monitoring Data Reader is one of the roles the
# bootstrap condition allows; re-run ./bootstrap/github-oidc.bash create first.
resource "azurerm_role_assignment" "grafana_monitor_reader" {
  scope                            = azurerm_monitor_workspace.this.id
  role_definition_name             = "Monitoring Data Reader"
  principal_id                     = azurerm_dashboard_grafana.this.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# The apply identity administers Grafana, so dashboards can be managed from terraform.
# People are granted Grafana Viewer, Editor or Admin by hand, like cluster access.
resource "azurerm_role_assignment" "github_actions_grafana_admin" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azuread_service_principal.github_actions.object_id
  principal_type       = "ServicePrincipal"
}
