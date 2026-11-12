# Self-hosted GoatCounter: cookieless page view counts for autobutler.org and
# quark.autobutler.org, kept on our own infrastructure. Both sites count into the one
# GoatCounter site at goatcounter_url; each page view's path is prefixed with its host, so
# the two stay apart on the dashboard.
#
# To upgrade, change goatcounter_version and goatcounter_sha256 together and merge. The
# setup script re-runs in place: it copies the database, swaps the binary and restarts
# with -automigrate.
#
# AFTER THE FIRST APPLY, by hand: read the generated admin password on the VM, and point
# both sites' beacon at goatcounter_count_url. modules/goatcounter/README.md has the exact
# commands.
resource "azurerm_resource_group" "goatcounter" {
  name     = "goatcounter"
  location = var.location
  tags     = local.tags
}

module "goatcounter" {
  source = "../../modules/goatcounter"

  name_prefix         = "goatcounter"
  resource_group_name = azurerm_resource_group.goatcounter.name
  location            = var.location

  goatcounter_version = var.goatcounter_version
  goatcounter_sha256  = var.goatcounter_sha256
  admin_email         = var.goatcounter_admin_email

  admin_ssh_public_key = var.goatcounter_ssh_public_key

  storage_account_name = "stautobutlergoatcounter"

  dns_zone_name                = azurerm_dns_zone.cloud.name
  dns_zone_resource_group_name = azurerm_resource_group.dns.name
  dns_record_name              = "stats"

  tags = local.tags
}
