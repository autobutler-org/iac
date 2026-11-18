# factory.cloud.autobutler.org, an alias for the reserved ingress address, so replacing
# the address moves the name without an apply-read-apply loop.
resource "azurerm_dns_a_record" "factory" {
  name                = local.dns_record_name
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.ingress.id
  tags                = var.tags
}
