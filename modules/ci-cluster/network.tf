# 10.8.0.0/16, not 10.0.0.0/16. schmeide and headscale each use 10.0.0.0/16 in their own
# VNets. Those VNets are not peered today, but reusing the range would make a later
# peering impossible. The node subnet is a /22: Azure CNI overlay does not take a pod
# address from it, so this only has to hold the system node and up to three runners.
resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.8.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = local.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.8.0.0/22"]
}

# The control-plane identity has to be able to join the subnet before the cluster
# resource is created. Azure CLI would add this assignment itself. Terraform has to do
# it first, which is why the cluster depends_on this resource rather than only on the
# identity. Scoped to this VNet, not the subscription.
resource "azurerm_role_assignment" "control_network" {
  scope                            = azurerm_virtual_network.this.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
