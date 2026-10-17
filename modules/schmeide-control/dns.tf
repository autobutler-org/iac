# An alias A record to the public IP resource, as for headscale: it follows the IP if that is
# ever replaced, and it is known at plan time, so there is no apply-read-apply loop. See
# modules/headscale/dns.tf.
resource "azurerm_dns_a_record" "this" {
  name                = var.dns_record_name
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.this.id
  tags                = var.tags
}
