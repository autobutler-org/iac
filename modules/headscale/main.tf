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

  # One knob drives all four. Setting the size to an Arm SKU and leaving the image or the
  # downloads on amd64 produces a VM that boots and then fails inside the setup script --
  # a dpkg architecture error buried in extension logs, not a plan-time failure. Deriving
  # them makes that combination unrepresentable.
  #
  # Go and Debian happen to agree on "arm64"/"amd64"; the Azure image SKU does not, hence
  # the lookup rather than string interpolation.
  image_sku = var.vm_architecture == "arm64" ? "server-arm64" : "server"

  # Rendered here rather than inline in the extension so the settings block stays readable,
  # and so a `terraform console` can print the script that would actually be sent.
  #
  # The script carries var.provisioning_secret, so the rendered string is sensitive and the
  # console prints "(sensitive value)" for it. Wrap it in nonsensitive() to read it, and
  # only ever with a dummy secret exported.
  #
  # The secret is rendered into the script rather than passed to it: CustomScript takes
  # `script` or `commandToExecute`, never both, so an environment variable would mean
  # inlining this whole script into commandToExecute, where it is also visible in `ps` on
  # the VM for as long as it runs. It is base64-encoded so no value can break the shell
  # quoting around it.
  setup_script = templatefile("${path.module}/templates/setup-headscale.bash.tftpl", {
    domain               = var.headscale_domain
    base_domain          = var.headscale_base_domain
    admin_email          = var.admin_email
    arch                 = var.vm_architecture
    go_version           = var.go_version
    headscale_version    = var.headscale_version
    repo_url             = var.provisioning_repo_url
    repo_ref             = var.provisioning_repo_ref
    provisioning_package = var.provisioning_package
    service_name         = var.provisioning_service_name
    source_dir           = var.provisioning_source_dir
    config_dir           = var.provisioning_config_dir
    secret_b64           = base64encode(var.provisioning_secret)
  })
}
