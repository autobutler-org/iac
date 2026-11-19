# The factory MVP (autobutler-org/factory#1): its own AKS cluster, a PostgreSQL server
# with the factory and substrate databases (off, see below), a Key Vault, Substrate
# snapshot storage and factory.cloud.autobutler.org. modules/factory/README.md has the
# steps a person takes after the first apply. Apply happens from main via CI.
resource "azurerm_resource_group" "factory" {
  name     = "autobutler-factory"
  location = var.location
  tags     = local.tags
}

module "factory" {
  source = "../../modules/factory"

  resource_group_name = azurerm_resource_group.factory.name
  location            = var.location
  # Off: Azure refuses to create the flexible server for this subscription
  # (SkuNotAvailable for B_Standard_B1ms in eastus2 and centralus), so PostgreSQL runs in
  # the cluster from the factory chart. What was tried and what is left to try is in
  # modules/factory/postgresql.tf. https://github.com/autobutler-org/iac/issues/124
  postgres_enabled  = false
  postgres_location = "centralus"
  tags              = local.tags

  dns_zone_name                = azurerm_dns_zone.cloud.name
  dns_zone_resource_group_name = azurerm_resource_group.dns.name
}
