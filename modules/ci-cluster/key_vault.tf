# The Actions GitHub App private key. Terraform creates the vault and the runner
# identity's read access, and never a secret value: a value set here would land in state
# and in the planfile artifact. A person sets one secret after the first apply:
#
#   github-app-private-key   the Actions GitHub App's private key, the whole PEM
#
# The App does not exist yet, and terraform does not create it. This is not a second
# app, and it is not the schmeide app, which has its own vault and its own copy of a
# secret with the same name.
#
# Access policies rather than Azure RBAC, for the same reason as
# modules/schmeide-control. CI applies as a Contributor, which can write access policies
# (they are part of the vault resource) but cannot create role assignments. The
# bootstrap script's constrained Role Based Access Control Administrator grant does not
# change that for this vault: Key Vault data-plane roles are not in the condition's
# allow list, so an RBAC grant here would still fail the apply. Policies added by hand,
# such as the one the person setting the secret gives themselves, are left alone. This
# module owns only the access policy below, and the vault declares none inline.
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

  # The secret value exists nowhere else in this repo. Recreating the vault means a
  # person has to set it again.
  lifecycle {
    prevent_destroy = true
  }
}

# Get and List: the runner reads github-app-private-key by name. It does not set or
# delete secrets, and this module creates none.
resource "azurerm_key_vault_access_policy" "runner" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.runner.principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}
