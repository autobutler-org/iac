# One burstable server for both databases. No HA, no geo-redundant backup.
#
# centralus, not eastus: `az postgres flexible-server list-skus -l eastus` reports
# provisioning restricted for this subscription, and eastus2 lists B_Standard_B1ms but
# refused to create it (SkuNotAvailable) on 2026-11-18. The cluster is roughly 25 ms
# away, which a work queue polled every few seconds does not notice.
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
  length  = 40
  special = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = local.postgres_server_name
  resource_group_name = var.resource_group_name
  location            = var.postgres_location
  version             = "17"
  sku_name            = "B_Standard_B1ms"
  storage_mb          = 32768

  administrator_login               = local.postgres_admin_login
  administrator_password_wo         = ephemeral.random_password.postgres_admin.result
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
  for_each = local.postgres_databases

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "cluster_egress" {
  name             = "aks-egress"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = azurerm_public_ip.egress.ip_address
  end_ip_address   = azurerm_public_ip.egress.ip_address
}
