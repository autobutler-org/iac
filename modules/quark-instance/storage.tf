# Quark's state lives on Azure Files, not in the container group, so the container group is
# disposable: a version bump replaces it and the new one mounts the same share. The share can
# also be mounted by any other container group, or by `az storage file download`, to move the
# instance somewhere else.
#
# Shared key access stays on because ACI mounts Azure Files with the account key; it has no
# identity-based mount.
resource "azurerm_storage_account" "data" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true

  share_properties {
    retention_policy {
      days = 7
    }
  }

  tags = var.tags

  # Holds every file and the SQLite database of the instance.
  lifecycle {
    prevent_destroy = true
  }
}

# Mounted at /var/lib/quark: the whole quark root, so tsnet/ (tailnet enrollment) survives
# alongside data/. See docs/container.md in the quark repo.
resource "azurerm_storage_share" "quark" {
  name               = "quark"
  storage_account_id = azurerm_storage_account.data.id
  quota              = var.data_share_quota_gb

  lifecycle {
    prevent_destroy = true
  }
}

# Caddy's certificates and ACME account. Without it every replacement re-issues from Let's
# Encrypt, and a few version bumps in a week hit the duplicate-certificate rate limit.
resource "azurerm_storage_share" "caddy" {
  name               = "caddy"
  storage_account_id = azurerm_storage_account.data.id
  quota              = 1

  lifecycle {
    prevent_destroy = true
  }
}
