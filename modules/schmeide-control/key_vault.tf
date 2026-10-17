data "azurerm_client_config" "current" {}

# The control node's three secrets. Terraform creates the vault and the VM's read access,
# and never a secret value: a value set here would land in state and in the planfile
# artifact. A person sets them once, by hand, after the first apply:
#
#   webhook-secret           the GitHub App's webhook secret
#   github-app-private-key   the GitHub App's private key, the whole PEM
#   runner-tokens            '<steward login>:<token>' entries, comma-separated
#
# Access policies rather than Azure RBAC, deliberately. CI applies as a Contributor, which
# can write access policies (they are part of the vault resource) but cannot create role
# assignments, so an RBAC grant here would fail the apply. Policies added by hand, such as
# the one the person setting the secrets gives themselves, are left alone: this module owns
# only the one azurerm_key_vault_access_policy below, and the vault declares none inline.
resource "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = false
  soft_delete_retention_days = 7

  tags = var.tags

  # The secret values exist nowhere else; recreating the vault means setting them all again.
  lifecycle {
    prevent_destroy = true
  }
}

# Get only: the VM reads the three secrets by name and needs nothing else.
resource "azurerm_key_vault_access_policy" "vm" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_virtual_machine.this.identity[0].principal_id

  secret_permissions = [
    "Get",
  ]
}
