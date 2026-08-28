resource "azurerm_linux_virtual_machine" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  # The default, Standard_B1s, is announced for retirement and tflint is right to say so.
  # It is kept anyway, deliberately, and suppressed here rather than by switching the rule
  # off repo-wide -- the warning is correct everywhere else and this is the one place that
  # has an answer for it.
  #
  # The alternatives, checked against what this subscription can actually deploy in eastus:
  #
  #   every x64 burstable size  B1s/B1ms/B2s/B2ms are all flagged; the whole v1 B-series is
  #                             retiring together, so moving within it buys nothing
  #   Standard_B1ls             not flagged, but 0.5 GB RAM cannot compile the provisioning
  #                             binary -- the Go toolchain alone will not fit
  #   Bsv2 (B2ts_v2 et al)      not offered here in x64; eastus lists only Arm64 variants,
  #                             and the setup script fetches linux-amd64 Go and an amd64
  #                             headscale .deb, so that is a script change, not a size change
  #   Standard_D2s_v5           not flagged and would work, at roughly seven times the cost
  #                             of a host whose entire job is to relay control-plane traffic
  #
  # So: match the existing autobutler host until the Arm64 move is made deliberately, which
  # is the real fix and wants its own change.
  # tflint-ignore: azurerm_linux_virtual_machine_retired_size
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
    sku       = "server"
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
