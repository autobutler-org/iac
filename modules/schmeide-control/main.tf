# A schmeide control node on a single Azure VM: `schmeide control` in a container, with
# Caddy in front of its webhook listener, NATS published directly, and JetStream state on a
# separate managed disk.
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

  hostname = "${var.dns_record_name}.${var.dns_zone_name}"

  # Same lookup as modules/headscale: the Azure image SKU and the CPU architecture do not
  # share a vocabulary, and deriving one from the other keeps them from drifting.
  image_sku = var.vm_architecture == "arm64" ? "server-arm64" : "server"

  # Rendered here so a `terraform console` can print the script that would actually be sent.
  # It carries no secret: the VM reads those from the Key Vault itself, at every service
  # start, with its managed identity. See templates/setup-schmeide-control.bash.tftpl.
  setup_script = templatefile("${path.module}/templates/setup-schmeide-control.bash.tftpl", {
    hostname      = local.hostname
    image         = "ghcr.io/autobutler-org/schmeide:${var.schmeide_version}"
    vault_uri     = azurerm_key_vault.this.vault_uri
    github_app_id = var.github_app_id
    allowed_orgs  = join(",", var.allowed_orgs)
  })
}
