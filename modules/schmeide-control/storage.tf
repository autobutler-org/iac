# schmeide's state lives on its own managed disk, not the OS disk, so the VM is disposable:
# a replacement attaches this same disk at the same LUN, and the setup script mounts it
# without formatting it. It holds two things, under /srv/schmeide:
#
#   data/   mounted at /data, SCHMEIDE_DATA_DIR -- the JetStream store: every queued job
#   caddy/  Caddy's certificates and ACME account, which NATS also serves. Without it every
#           replacement re-issues, and a few in a week hit Let's Encrypt's duplicate limit.
#
# Standard_LRS bills by tier and the smallest HDD tier is 32 GiB, so asking for less saves
# nothing.
resource "azurerm_managed_disk" "data" {
  name                 = "${local.name}-data"
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# LUN 0 is what the setup script looks for. Host caching is off: JetStream fsyncs, and a
# read-write host cache would acknowledge writes the disk does not hold yet.
resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = 0
  caching            = "None"
}
