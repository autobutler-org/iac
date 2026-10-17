# The schmeide control node (github.com/autobutler-org/schmeide): the schmeide GitHub App's
# webhook endpoint, and the NATS server runners pull jobs from.
#
# To upgrade, change schmeide_control_version and merge. The setup script re-runs in place
# and restarts the container; the JetStream store on the data disk is untouched. Renovate
# opens a pull request for each new schmeide tag, and unlike quark's it does not auto-merge.
#
# AFTER THE FIRST APPLY, by hand -- terraform never holds a secret value: set the three
# Key Vault secrets, point the GitHub App's webhook at schmeide_control_webhook_url, and
# point runners at schmeide_control_nats_url. modules/schmeide-control/README.md has the
# exact commands.
resource "azurerm_resource_group" "schmeide_control" {
  name     = "schmeide-control"
  location = var.location
  tags     = local.tags
}

module "schmeide_control" {
  source = "../../modules/schmeide-control"

  name_prefix         = "schmeide-control"
  resource_group_name = azurerm_resource_group.schmeide_control.name
  location            = var.location

  schmeide_version = var.schmeide_control_version
  github_app_id    = var.schmeide_github_app_id
  allowed_orgs     = ["autobutler-org"]
  key_vault_name   = "kv-schmeide-control"

  admin_ssh_public_key = var.schmeide_control_ssh_public_key

  dns_zone_name                = azurerm_dns_zone.cloud.name
  dns_zone_resource_group_name = azurerm_resource_group.dns.name
  dns_record_name              = "schmeide"

  tags = local.tags
}
