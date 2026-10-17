resource "azurerm_linux_virtual_machine" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  # The headscale host's size, for the same reasons: see modules/headscale/compute.tf. Unlike
  # headscale nothing compiles on this host, so 1 GiB only has to hold docker, Caddy and
  # schmeide. If JetStream outgrows it, Standard_B2pls_v2 (4 GiB) is the next step.
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

  # Reads the Key Vault secrets at every start of schmeide-control.service. See key_vault.tf.
  identity {
    type = "SystemAssigned"
  }

  # No prevent_destroy, unlike headscale: nothing on the OS disk is worth keeping. JetStream
  # and Caddy's certificates live on the data disk in storage.tf, the secrets in the Key
  # Vault, and the setup script rebuilds everything else. Replacing the VM is a short outage.
  #
  # source_image_reference.version is "latest", so a new Ubuntu publish would otherwise
  # show up as a replacement diff on an unrelated apply.
  lifecycle {
    ignore_changes = [
      source_image_reference[0].version,
    ]
  }
}

# Runs the setup script, through the CustomScript extension rather than custom_data for the
# reason headscale gives: a changed script, which includes every schmeide version bump,
# re-runs in place instead of replacing the VM. See modules/headscale/compute.tf for how the
# extension re-runs and why the script sits in protected_settings.
#
# After the disk attachment, because the script mounts that disk.
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

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.data,
  ]
}

resource "azurerm_virtual_machine_extension" "aad_ssh_login" {
  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}
