# The control server's public A record.
#
# An ALIAS record (target_resource_id) rather than a literal address (records). The record
# then resolves through to whatever address the public IP resource currently holds, so a
# replaced IP does not need a second apply to fix DNS, and there is no window where the
# record points at an address Azure has handed to someone else.
#
# It also removes the ordering problem a literal record has: ip_address is unknown until
# the IP exists, so a literal record forces the operator to apply, read the address, write
# it down and apply again. The alias is known at plan time because it references a resource.
#
# Created before the VM (the extension depends on the VM, the VM on the NIC, the NIC on the
# IP), so DNS is usually live by the time the setup script runs certbot. Usually, not
# always -- see the certbot comment in the template. A failure there is non-fatal by design.
resource "azurerm_dns_a_record" "this" {
  count = var.dns_zone_name == null ? 0 : 1

  # Zone-relative name. "network.quark" in zone "ts.autobutler.org" is
  # network.quark.ts.autobutler.org. The precondition below is what stops a mismatched
  # domain and zone from silently producing a record in the wrong place.
  name                = trimsuffix(var.headscale_domain, ".${var.dns_zone_name}")
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.this.id
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = endswith(var.headscale_domain, ".${var.dns_zone_name}")
      error_message = "headscale_domain (${var.headscale_domain}) must be inside dns_zone_name (${var.dns_zone_name}), or terraform cannot create its record. Either move the domain into the zone or set dns_zone_name to null and manage the record externally."
    }

    precondition {
      condition     = var.dns_zone_resource_group_name != null
      error_message = "dns_zone_resource_group_name is required when dns_zone_name is set."
    }
  }
}
