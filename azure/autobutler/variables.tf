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
  default     = "network.quark.ts.autobutler.org"
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

variable "quark_headscale_provisioning_secret" {
  description = "Shared secret for the quark tailnet's provisioning service. No default: CI sets it as TF_VAR_quark_headscale_provisioning_secret from the QUARK_PROVISIONING_SECRET organization secret, which quark's release build stamps into the client too. A local plan needs it exported the same way."
  type        = string
  sensitive   = true
}

variable "tailnet_dns_zone" {
  description = "Public DNS zone delegated to Azure for tailnet records. Its parent stays at Porkbun; only this label is delegated."
  type        = string
  default     = "ts.autobutler.org"
}
