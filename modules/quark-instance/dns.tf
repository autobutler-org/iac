# The instance's public name, a CNAME to the container group's Azure FQDN. ACI cannot be
# the target of an alias record, and its IP changes on every replacement, so a CNAME to
# the stable FQDN is what survives a version bump.
resource "azurerm_dns_cname_record" "quark" {
  name                = var.dns_record_name
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
  ttl                 = 300
  record              = azurerm_container_group.quark.fqdn
  tags                = var.tags
}
