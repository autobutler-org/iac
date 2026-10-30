# Basic, same region as the cluster. admin_enabled is the credential switch: the provider
# has no shared-key argument on a registry the way a storage account does, and the admin
# user is what those keys would belong to. Public network access stays on. There is no
# private endpoint in this change.
#
# role_assignment_mode AbacRepositoryPermissions is the mode new registries are moving
# to. In that mode the legacy AcrPull role is not honored, so the kubelet gets Container
# Registry Repository Reader instead, and only pull. azurerm 5.11.0 accepts the argument.
resource "azurerm_container_registry" "this" {
  name                = local.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false

  public_network_access_enabled = true
  role_assignment_mode          = "AbacRepositoryPermissions"

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# The kubelet identity is the one AKS creates, not the runner identity and not the
# control-plane identity. It may not have replicated through Entra when this assignment
# is written, so the AAD check is skipped. Push is not granted.
resource "azurerm_role_assignment" "kubelet_acr" {
  scope                            = azurerm_container_registry.this.id
  role_definition_name             = "Container Registry Repository Reader"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Quark's CI image workflow pushes autobutlerci.azurecr.io/ci. Writer is the ABAC
# role that can push. The bootstrap condition has to list this role or CI cannot
# create the assignment. The image identity is new, so skip the AAD replication check.
resource "azurerm_role_assignment" "image_acr_push" {
  scope                            = azurerm_container_registry.this.id
  role_definition_name             = "Container Registry Repository Writer"
  principal_id                     = azurerm_user_assigned_identity.image.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
