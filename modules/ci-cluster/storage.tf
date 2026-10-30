# Not the quark release account. That one is anonymously readable because the quark
# client has no credential. This cache is private: shared keys are off, nested public
# access is off, and the runner identity is the only data-plane principal. Do not copy
# allow_nested_items_to_be_public or container_access_type from modules/quark. Public
# network access stays on; there is no private endpoint in this change. Blob auth is
# Entra ID, which is why shared keys are off.
resource "azurerm_storage_account" "cache" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  # "Enabled", not the deprecated bool. Public on purpose: no private endpoint in this change.
  public_network_access = "Enabled"

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "cache" {
  name                  = local.cache_container_name
  storage_account_id    = azurerm_storage_account.cache.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# The runner identity, not the kubelet. Same replication caveat as the registry pull
# grant. Scoped to this account.
resource "azurerm_role_assignment" "runner_cache" {
  scope                            = azurerm_storage_account.cache.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.runner.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
