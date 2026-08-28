resource "azurerm_linux_virtual_machine" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  # Standard_B2pts_v2: 2 vCPU, 1 GiB, Arm64, burstable. It is the successor to the
  # Standard_B1s this replaced -- double the vCPU, the same memory, and cheaper
  # ($6.13/mo against $7.59 at eastus list price).
  #
  # Arm64 is not a preference here, it is the only burstable option. eastus offers no x64
  # Bsv2 at all (no B2ts_v2, B2ls_v2 or B2s_v2), and the entire v1 B-series is retiring
  # together, so there is no x64 burstable left to move to. The x64 alternatives are all
  # non-burstable and cost far more for a host whose whole job is relaying control-plane
  # traffic: D2als_v6 is $58.69/mo, D2s_v5 $70.08.
  #
  # headscale publishes a linux_arm64 .deb and Go a linux-arm64 toolchain, so nothing in
  # the setup script needs a fallback -- see var.vm_architecture, which drives both.
  #
  # Memory is the thing to watch, not the architecture: 1 GiB is unchanged from B1s, and
  # the script compiles the provisioning binary on the host. If that ever OOMs, the next
  # step is Standard_B2pls_v2 (4 GiB, $24.53/mo), not a return to x64.
  size           = var.vm_size
  admin_username = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.this.id,
  ]
  tags = var.tags

  # Key-only. The AADSSHLoginForLinux extension below adds Entra ID as a second way in, so
  # there is no path that accepts a password.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "${local.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = local.image_sku
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # The OS disk holds headscale's sqlite database at /var/lib/headscale/db.sqlite, which is
  # the entire tailnet: every node registration, pre-auth key and route. It is not backed up
  # anywhere and cannot be reconstructed -- losing it means re-enrolling every device by
  # hand. Replacing this VM destroys that disk.
  #
  # This is also why setup runs through the CustomScript extension rather than custom_data:
  # custom_data is immutable, so editing the setup script would force replacement and take
  # the database with it. The extension re-runs in place instead.
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

# Runs the setup script. Unlike custom_data this is a mutable resource: changing the
# rendered script updates the extension and re-executes it on the running VM, leaving the
# OS disk -- and the headscale database on it -- untouched.
#
# The script is passed via protected_settings rather than settings. It contains no secret
# today, but protected_settings is encrypted at rest and never echoed back by the ARM API,
# and this is the channel any future credential would travel down. settings would publish
# it in plain text to anyone with reader on the resource group.
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

# Lets Entra ID identities SSH in with `az ssh vm`, subject to the Virtual Machine
# Administrator/User Login roles, so access can be revoked centrally instead of by editing
# authorized_keys. The admin_ssh_key above stays as the break-glass path for when Entra or
# the extension itself is the thing that is broken.
resource "azurerm_virtual_machine_extension" "aad_ssh_login" {
  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}
