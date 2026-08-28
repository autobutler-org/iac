# A headscale control server on a single Azure VM: nginx terminating TLS in front of
# headscale on loopback, plus a provisioning sidecar that mints pre-auth keys.
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

  # Rendered here rather than inline in the extension so the settings block stays readable,
  # and so a `terraform console` can print the script that would actually be sent.
  setup_script = templatefile("${path.module}/templates/setup-headscale.bash.tftpl", {
    domain               = var.headscale_domain
    base_domain          = var.headscale_base_domain
    admin_email          = var.admin_email
    go_version           = var.go_version
    headscale_version    = var.headscale_version
    repo_url             = var.provisioning_repo_url
    repo_branch          = var.provisioning_repo_branch
    provisioning_package = var.provisioning_package
    service_name         = var.provisioning_service_name
    source_dir           = var.provisioning_source_dir
    config_dir           = var.provisioning_config_dir
  })
}
