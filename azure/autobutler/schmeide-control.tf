# The schmeide control node (github.com/autobutler-org/schmeide): the schmeide GitHub App's
# webhook endpoint, and the NATS server runners pull jobs from.
#
# To upgrade, change schmeide_control_version and merge. The setup script re-runs in place
# and restarts the container; the JetStream store on the data disk is untouched. Renovate
# opens a pull request for each new schmeide tag, and unlike quark's it does not auto-merge.
#
# AFTER THE FIRST APPLY, by hand -- terraform never holds a secret value:
#   1. Give yourself secret access to the vault in the schmeide_control_key_vault_name
#      output, then set webhook-secret, github-app-private-key (the PEM, with --file) and
#      runner-tokens. See modules/schmeide-control/key_vault.tf.
#   2. Set the GitHub App's webhook URL to the schmeide_control_webhook_url output.
#   3. Point runners at the schmeide_control_nats_url output.
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
