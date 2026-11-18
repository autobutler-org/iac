# Access policies, not RBAC, for the reason in modules/ci-cluster/key_vault.tf. Terraform
# writes one secret, the PostgreSQL admin password, write-only. A person writes the
# per-application database URLs after creating their roles; see the module README.
resource "azurerm_key_vault" "this" {
  name                = local.key_vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = false
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# The apply identity writes the admin password. It reads secrets back only because the
# provider reads a secret's metadata after writing it.
resource "azurerm_key_vault_access_policy" "github_actions" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azuread_service_principal.github_actions.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
  ]
}

resource "azurerm_key_vault_secret" "postgres_admin_password" {
  name             = "postgres-admin-password"
  key_vault_id     = azurerm_key_vault.this.id
  value_wo         = ephemeral.random_password.postgres_admin.result
  value_wo_version = 1
  content_type     = "login ${local.postgres_admin_login} on ${azurerm_postgresql_flexible_server.this.fqdn}"

  depends_on = [azurerm_key_vault_access_policy.github_actions]

  # The only copy of the admin password outside the server.
  lifecycle {
    prevent_destroy = true
  }
}
