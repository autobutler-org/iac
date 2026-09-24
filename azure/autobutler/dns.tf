# Azure DNS for the tailnet subdomain.
#
# autobutler.org itself stays at Porkbun, deliberately. Delegating the apex would move
# GitHub Pages, demo.autobutler.org and -- the part that actually bites -- Porkbun's mail
# forwarding (MX to fwd1.porkbun.com) and its SPF include. That is a lot of blast radius
# for one A record, and mail breakage is the kind that goes unnoticed for a week.
#
# quark.autobutler.org could not be used either: it is the CNAME for the quark website.
#
# So one unused label is delegated instead. Everything under ts.autobutler.org is managed
# here; everything else stays where it is.
#
# ONE-TIME MANUAL STEP: after the first apply, read the `tailnet_dns_zone_nameservers`
# output and create the matching NS records for `ts` at Porkbun. Until that delegation
# exists the zone resolves for nobody and certbot cannot issue. This is the only DNS
# action outside terraform, and it never has to be repeated -- records under the zone are
# managed from here from then on.
resource "azurerm_resource_group" "dns" {
  name     = "autobutler-dns"
  location = var.location
  tags     = local.tags
}

resource "azurerm_dns_zone" "tailnet" {
  name                = var.tailnet_dns_zone
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.tags
}

# Public services, delegated the same way as ts above and for the same reasons. ts is for
# the tailnet; this one is for things served on the open internet.
#
# ONE-TIME MANUAL STEP: after the first apply, create NS records for `cloud` at Porkbun from
# the `cloud_dns_zone_nameservers` output. Until then nothing under it resolves, and Caddy
# on the quark instance keeps retrying its certificate.
resource "azurerm_dns_zone" "cloud" {
  name                = var.cloud_dns_zone
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.tags
}
