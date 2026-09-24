# Headscale control server for the quark tailnet.
#
# modules/headscale/README.md is the contract with the quark codebase: the endpoints it
# exposes, the constant in remoteutil.go that has to point at them, and where the
# provisioning service's household key comes from. Read it before changing a domain here.
#
# VERIFYING-HEADSCALE.md, next to this file, is how to prove the server works after an
# apply -- without any quark change, because the stock Tailscale client takes
# --login-server. Test the infrastructure before the quark PR exists, or a failure could
# be in either repo with no way to tell which.
#
# The resource group already existed (created by hand alongside the autobutler one) and was
# adopted with an import block rather than created here.
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

  # A release tag, never a branch: the setup script re-clones on every apply, and a merged
  # branch gets deleted (the old feat/1876 pin failed that way). v0.43.0 is the release
  # with quark#2358 (one headscale user per Quark, signed with PROVISIONING_HOUSEHOLD_KEY)
  # and quark#1879 (no provisioning secret), matching the setup script's env.
  provisioning_repo_ref = "v0.43.0"

  # With the zone passed in, the module owns its own A record as an alias to the public IP
  # resource. That removes the apply -> read the IP -> create the record -> apply again
  # loop the manual approach needs, and the record follows the IP if it is ever replaced.
  dns_zone_name                = azurerm_dns_zone.tailnet.name
  dns_zone_resource_group_name = azurerm_resource_group.dns.name

  tags = local.tags
}
