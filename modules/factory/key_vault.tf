# Access policies, not RBAC, for the reason in modules/ci-cluster/key_vault.tf. Terraform
# writes one secret, the PostgreSQL admin password, write-only, and only while the managed
# server is enabled. A person writes the database URLs; see the module README.
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

# Gated with the server: without one the password is meaningless. No apply ever
# created it (both applies failed on the server it waits for), so it is in no state
# and turning postgres_enabled off destroys nothing.
resource "azurerm_key_vault_secret" "postgres_admin_password" {
  count = var.postgres_enabled ? 1 : 0

  name             = "postgres-admin-password"
  key_vault_id     = azurerm_key_vault.this.id
  value_wo         = ephemeral.random_password.postgres_admin[0].result
  value_wo_version = 1
  content_type     = "login ${local.postgres_admin_login} on ${azurerm_postgresql_flexible_server.this[0].fqdn}"

  depends_on = [azurerm_key_vault_access_policy.github_actions]

  # The only copy of the admin password outside the server.
  lifecycle {
    prevent_destroy = true
  }
}
