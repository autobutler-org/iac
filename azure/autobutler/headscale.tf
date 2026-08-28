# Headscale control server for the quark tailnet.
#
# The resource group already existed (created by hand alongside the autobutler one) and is
# adopted in imports.tf rather than created here -- see the comment there.
#
# There is a second, hand-built headscale host in autobutler-headscale serving a live
# tailnet. It is deliberately NOT managed by this module yet: adopting a running control
# server is its own change, with its own blast radius, and nothing about this one depends
# on it. The module is written to be instantiated twice when that happens.
resource "azurerm_resource_group" "quark_headscale" {
  name     = "quark-headscale"
  location = var.location
  tags     = local.tags
}

module "quark_headscale" {
  source = "../../modules/headscale"

  name_prefix         = "quark-headscale"
  resource_group_name = azurerm_resource_group.quark_headscale.name
  location            = var.location

  headscale_domain      = var.quark_headscale_domain
  headscale_base_domain = var.quark_headscale_base_domain
  admin_email           = var.quark_headscale_admin_email
  admin_username        = "quark"
  admin_ssh_public_key  = var.quark_headscale_ssh_public_key

  # With the zone passed in, the module owns its own A record as an alias to the public IP
  # resource. That removes the apply -> read the IP -> create the record -> apply again
  # loop the manual approach needs, and the record follows the IP if it is ever replaced.
  dns_zone_name                = azurerm_dns_zone.tailnet.name
  dns_zone_resource_group_name = azurerm_resource_group.dns.name

  tags = local.tags
}
