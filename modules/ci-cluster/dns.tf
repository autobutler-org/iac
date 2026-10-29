# Static Standard address for the Argo CD UI. The A record aliases this resource, so
# replacing the address updates the name without an apply-read-apply loop. Same pattern
# as modules/schmeide-control/dns.tf.
#
# The IP lives in the cluster resource group, not the node resource group AKS owns.
# The Argo Service, installed later, attaches it by name. The control-plane identity
# needs Network Contributor on this address or that attach fails. The cluster create
# waits on the assignment so the permission exists before any Service is applied.
resource "azurerm_public_ip" "argocd" {
  name                = local.argocd_public_ip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "control_argocd_ip" {
  scope                            = azurerm_public_ip.argocd.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# argo.errand in cloud.autobutler.org. The label is two parts because the product name
# sits under the zone and Argo sits under the product. errand.cloud.autobutler.org is
# the management UI and is not created here. That UI does not exist yet.
resource "azurerm_dns_a_record" "argocd" {
  name                = local.argocd_dns_record_name
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.argocd.id
  tags                = var.tags
}
