resource "azurerm_linux_virtual_machine" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  # The headscale host's size, for the same reasons: see modules/headscale/compute.tf.
  # GoatCounter is one static Go binary counting a few hundred page views a day, so 1 GiB
  # is plenty; nothing is compiled on the host.
  size           = var.vm_size
  admin_username = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.this.id,
  ]
  tags = var.tags

  # Key-only, plus Entra ID through the AADSSHLoginForLinux extension below, as for headscale.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "${local.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = local.image_sku
    version   = "latest"
  }

  # Writes the daily backup to the blob container in storage.tf. See the role assignment there.
  identity {
    type = "SystemAssigned"
  }

  # The OS disk holds GoatCounter's SQLite database at /var/lib/goatcounter/db.sqlite3:
  # every page view since the server started. The daily backup in storage.tf bounds a loss
  # to one day, but replacing this VM still loses that day and forces a restore by hand.
  #
  # SQLite is on the local disk and not on Azure Files on purpose: SQLite's locking does not
  # hold over SMB, which is how a database gets corrupted rather than just slow.
  #
  # Setup runs through the CustomScript extension rather than custom_data for the reason
  # headscale gives: custom_data is immutable, so a GoatCounter version bump would replace
  # the VM. The extension re-runs in place instead.
  #
  # source_image_reference.version is "latest", so a new Ubuntu publish would otherwise
  # show up as a replacement diff on an unrelated apply.
  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      source_image_reference[0].version,
    ]
  }
}

# Runs the setup script. A changed script -- which includes every GoatCounter version bump --
# re-runs in place on the existing VM. See modules/headscale/compute.tf for how the extension
# re-runs and why the script sits in protected_settings.
resource "azurerm_virtual_machine_extension" "cloud_init" {
  name                       = "cloud-init"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  protected_settings = jsonencode({
    script = base64encode(local.setup_script)
  })
}

# Entra ID SSH with `az ssh vm`, subject to the Virtual Machine Administrator/User Login
# roles, as for headscale. The admin_ssh_key above is the break-glass path.
resource "azurerm_virtual_machine_extension" "aad_ssh_login" {
  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}
