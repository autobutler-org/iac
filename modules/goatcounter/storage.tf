# Daily backups of GoatCounter's SQLite database. Private, like the CI cache in
# modules/ci-cluster and unlike the quark release account: shared keys are off, nested
# public access is off, and the VM's managed identity is the only data-plane principal.
# Do not copy allow_nested_items_to_be_public or container_access_type from modules/quark.
resource "azurerm_storage_account" "backup" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # Cool: written once a day, read only for a restore. A few MiB a day costs pennies in
  # either tier, and Cool's early-deletion charge is moot with retention above 30 days.
  access_tier = "Cool"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  # Public endpoint, Entra ID auth, as for the CI cache: the VM reaches it over the internet
  # with its managed identity's token. A private endpoint would cost more than the VM.
  public_network_access = "Enabled"

  # Soft delete, so a backup deleted by mistake -- or by a lifecycle rule set too short --
  # can be undeleted for a week.
  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags

  # The backups exist nowhere else; recreating the account loses every one of them.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "backup" {
  name                  = "backups"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# Each run uploads a new, dated blob and never overwrites one, so old backups only go away
# through this rule.
resource "azurerm_storage_management_policy" "backup" {
  storage_account_id = azurerm_storage_account.backup.id

  rule {
    name    = "expire-old-backups"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${azurerm_storage_container.backup.name}/"]
    }

    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = var.backup_retention_days
      }
    }
  }
}

# Write access for the backup job, scoped to the one container. Storage Blob Data
# Contributor is one of the roles the CI identity's constrained Role Based Access Control
# Administrator grant may assign (bootstrap/github-oidc.bash), so CI can apply this.
resource "azurerm_role_assignment" "vm_backup" {
  scope                            = azurerm_storage_container.backup.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_linux_virtual_machine.this.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
