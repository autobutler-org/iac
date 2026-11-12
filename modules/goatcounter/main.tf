# A GoatCounter (https://www.goatcounter.com) server on a single Azure VM: cookieless page
# view counts for the org's static sites, kept on our own infrastructure instead of
# goatcounter.com. GoatCounter serves HTTPS itself, with its built-in ACME client, so there
# is no reverse proxy; its SQLite database lives on the VM's OS disk and is copied to a
# private blob container once a day.
#
# A shared module has no backend, so unlike a root module (where the terraform block lives
# in backend.tf) this module's terraform block lives in main.tf. The constraints are floors,
# not pins -- the root module in azure/<subscription>/ is where versions actually get set.
terraform {
  required_version = ">= 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
  }
}

locals {
  # Every resource name derives from this, so the module can be instantiated more than once
  # in a subscription without collisions.
  name = var.name_prefix

  # The one hostname GoatCounter answers on. It is the site's vhost in the database, the
  # name its ACME client requests a certificate for, and the A record in dns.tf.
  hostname = "${var.dns_record_name}.${var.dns_zone_name}"

  # Same lookup as modules/headscale: the Azure image SKU and the CPU architecture do not
  # share a vocabulary, and deriving one from the other keeps them from drifting.
  image_sku = var.vm_architecture == "arm64" ? "server-arm64" : "server"

  backup_container_url = "${azurerm_storage_account.backup.primary_blob_endpoint}${azurerm_storage_container.backup.name}"

  # Rendered here so a `terraform console` can print the script that would actually be sent.
  # It carries no secret: the admin password is generated on the VM and never passes
  # through Terraform, and the backup job authenticates with the VM's managed identity.
  setup_script = templatefile("${path.module}/templates/setup-goatcounter.bash.tftpl", {
    hostname             = local.hostname
    admin_email          = var.admin_email
    arch                 = var.vm_architecture
    goatcounter_version  = var.goatcounter_version
    goatcounter_sha256   = var.goatcounter_sha256
    backup_container_url = local.backup_container_url
  })
}
