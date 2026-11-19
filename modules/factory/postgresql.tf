# Off: Azure will not create a flexible server for this subscription (#124). The factory
# runs PostgreSQL in its cluster from the factory chart instead; see the module README.
# Everything below stays, working, behind var.postgres_enabled.
#
# What was tried, all B_Standard_B1ms, every one listed by
# `az postgres flexible-server list-skus -l <region>` and every one refused at create
# with SkuNotAvailable ("Specified SKU is not supported in this region"):
#   - eastus: provisioning restricted for the subscription outright, not attempted.
#   - eastus2, 2026-11-18, first apply of #121.
#   - centralus, 2026-11-19, after #122.
# Not tried yet: a General Purpose SKU (GP_Standard_D2ds_v5), westus3, and a support
# request to lift the subscription's flexible server restriction, which is the one most
# likely to work. Flip postgres_enabled in azure/autobutler/factory.tf to retry.
#
# One burstable server for both databases. No HA, no geo-redundant backup. The cluster
# is roughly 25 ms from centralus, which a work queue polled every few seconds does not
# notice.
#
# Public access, admitted by firewall from the cluster's static egress address only.
# Nothing in this repo uses a private endpoint yet, and VNet injection needs the server
# in the cluster's region. TLS is required by the server's default.
#
# The admin password is generated during the apply and written to two write-only
# arguments, here and in the vault. It is in no variable, plan or state. Bump
# administrator_password_wo_version and the secret's value_wo_version together to
# rotate it.
ephemeral "random_password" "postgres_admin" {
  count = var.postgres_enabled ? 1 : 0

  length  = 40
  special = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  count = var.postgres_enabled ? 1 : 0

  name                = local.postgres_server_name
  resource_group_name = var.resource_group_name
  location            = var.postgres_location
  version             = "17"
  sku_name            = "B_Standard_B1ms"
  storage_mb          = 32768

  administrator_login               = local.postgres_admin_login
  administrator_password_wo         = ephemeral.random_password.postgres_admin[0].result
  administrator_password_wo_version = 1
  public_network_access_enabled     = true
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  auto_grow_enabled                 = true

  tags = var.tags

  lifecycle {
    prevent_destroy = true
    # Azure picks a zone on create. Pinning one that the region does not offer this
    # SKU in fails the create.
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = var.postgres_enabled ? local.postgres_databases : toset([])

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "cluster_egress" {
  count = var.postgres_enabled ? 1 : 0

  name             = "aks-egress"
  server_id        = azurerm_postgresql_flexible_server.this[0].id
  start_ip_address = azurerm_public_ip.egress.ip_address
  end_ip_address   = azurerm_public_ip.egress.ip_address
}
