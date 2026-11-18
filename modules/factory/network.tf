# 10.9.0.0/16: not 10.0.0.0/16 (headscale, goatcounter) and not 10.8.0.0/16 (CI), so a
# later peering stays possible. Azure CNI overlay takes no pod address from the subnet.
resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.9.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = local.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.9.0.0/22"]
}

# The control-plane identity has to join the subnet before the cluster is created.
resource "azurerm_role_assignment" "control_network" {
  scope                            = azurerm_virtual_network.this.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# The factory Service attaches this address by name, the way the Argo Service in the CI
# cluster does. It lives in the factory resource group, not the node resource group.
resource "azurerm_public_ip" "ingress" {
  name                = local.ingress_public_ip_name
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

resource "azurerm_role_assignment" "control_ingress_ip" {
  scope                            = azurerm_public_ip.ingress.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Every connection out of the cluster leaves from this one address, so the PostgreSQL
# firewall can admit exactly the cluster. Without it AKS would pick a managed outbound IP
# that changes if the load balancer is rebuilt.
resource "azurerm_public_ip" "egress" {
  name                = local.egress_public_ip_name
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

resource "azurerm_role_assignment" "control_egress_ip" {
  scope                            = azurerm_public_ip.egress.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
