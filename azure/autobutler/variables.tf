variable "location" {
  description = "Default Azure region for resources in this subscription."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Extra tags merged over the defaults in main.tf and applied to everything here."
  type        = map(string)
  default     = {}
}

variable "quark_headscale_domain" {
  description = "Public FQDN the quark tailnet's headscale control server is reached on. An A record for it must point at the module's public IP before TLS can be issued."
  type        = string
  default     = "quark.ts.autobutler.org"
}

variable "quark_headscale_base_domain" {
  description = "MagicDNS base domain headscale hands out to nodes on the quark tailnet."
  type        = string
  default     = "headscale.quark.ts.autobutler.org"
}

variable "quark_headscale_admin_email" {
  description = "Email registered with Let's Encrypt for expiry notices on the quark headscale certificate."
  type        = string
  default     = "admin@autobutler.org"
}

variable "quark_headscale_ssh_public_key" {
  description = "SSH public key authorised on the quark headscale VM. Public half only, so committing it is what lets CI apply without a secret; it matches the key on the existing autobutler headscale host."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBFF2mZiRit7xR865+/Relyro1JBD1TzGT48XeC4XGSg autobutler.org@gmail.com"
}

variable "tailnet_dns_zone" {
  description = "Public DNS zone delegated to Azure for tailnet records. Its parent stays at Porkbun; only this label is delegated."
  type        = string
  default     = "ts.autobutler.org"
}

variable "quark_instance_version" {
  description = "Tag of ghcr.io/autobutler-org/quark the public quark instance runs, bare semver. Renovate bumps it; see quark-instance.tf."
  type        = string
  # renovate: datasource=docker depName=ghcr.io/autobutler-org/quark
  default = "0.60.0"
}

variable "cloud_dns_zone" {
  description = "Public DNS zone delegated to Azure for internet-facing services. Its parent stays at Porkbun; only this label is delegated."
  type        = string
  default     = "cloud.autobutler.org"
}

variable "schmeide_control_version" {
  description = "Tag of ghcr.io/autobutler-org/schmeide the control node runs. Renovate bumps it; see schmeide-control.tf."
  type        = string
  # renovate: datasource=docker depName=ghcr.io/autobutler-org/schmeide
  default = "0.0.9"
}

variable "schmeide_github_app_id" {
  description = "App ID of the schmeide GitHub App. Not a secret: it is in every token the App mints."
  type        = string
  default     = "5304111"
}

variable "schmeide_control_ssh_public_key" {
  description = "SSH public key authorized on the schmeide control VM. Public half only; the same key as the headscale host."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBFF2mZiRit7xR865+/Relyro1JBD1TzGT48XeC4XGSg autobutler.org@gmail.com"
}

# No `# renovate:` comment, unlike the image tags above. The setup script verifies the
# download against goatcounter_sha256, which Renovate cannot update, so a version-only bump
# would merge, apply, and then fail on the VM. Bump both by hand; the module README says how
# to get the checksum.
variable "goatcounter_version" {
  description = "GoatCounter release tag the stats server runs. Move goatcounter_sha256 with it; see goatcounter.tf."
  type        = string
  default     = "v2.7.0"
}

variable "goatcounter_sha256" {
  description = "SHA-256 of goatcounter-<goatcounter_version>-linux-arm64.gz from the GoatCounter release page. GoatCounter publishes no checksum file, so this was computed from the downloaded asset when the version was pinned."
  type        = string
  default     = "ff5b2670b858bbe48802dfdc74130b6dcde2de9f5c1229b838eb9132769307dd"
}

variable "goatcounter_admin_email" {
  description = "Login email of the GoatCounter admin user. Its password is generated on the VM, never in terraform."
  type        = string
  default     = "admin@autobutler.org"
}

variable "goatcounter_ssh_public_key" {
  description = "SSH public key authorized on the GoatCounter VM. Public half only; the same key as the headscale and schmeide hosts."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBFF2mZiRit7xR865+/Relyro1JBD1TzGT48XeC4XGSg autobutler.org@gmail.com"
}
