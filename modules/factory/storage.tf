# Substrate snapshot storage. Private, Entra-only, like the CI cache. Substrate's object
# store plugin speaks gs:// and s3:// only, not Azure Blob, so Substrate reaches this
# through an S3-compatible gateway chosen when Substrate is installed. Which identity
# that gateway uses, and its role on this account, come with it.
resource "azurerm_storage_account" "snapshots" {
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
  public_network_access           = "Enabled"

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

resource "azurerm_storage_container" "snapshots" {
  name                  = local.snapshot_container
  storage_account_id    = azurerm_storage_account.snapshots.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}
