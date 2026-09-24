# A public quark server running the released container image.
#
# To upgrade, change quark_instance_version and merge; CI replaces the container group and
# the new one mounts the same data share. Renovate does this on its own: it opens a pull
# request for each new quark tag and auto-merges it once the checks pass.
resource "azurerm_resource_group" "quark_instance" {
  name     = "quark-instance"
  location = var.location
  tags     = local.tags
}

module "quark_instance" {
  source = "../../modules/quark-instance"

  name                 = "quark-instance"
  resource_group_name  = azurerm_resource_group.quark_instance.name
  location             = var.location
  quark_version        = var.quark_instance_version
  dns_name_label       = "autobutler-quark"
  storage_account_name = "stquarkinstance"

  dns_zone_name                = azurerm_dns_zone.cloud.name
  dns_zone_resource_group_name = azurerm_resource_group.dns.name

  tags = local.tags
}
