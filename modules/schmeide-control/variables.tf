variable "name_prefix" {
  description = "Prefix for every resource this module creates. The VM takes this name verbatim; the rest append a suffix (-vnet, -pip, -nsg, -nic, -osdisk, -data). Also the public IP's DNS label, so it must be unique within the region."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the control node in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for every resource this module creates."
  type        = string
  default     = "eastus"
}

variable "schmeide_version" {
  description = "Tag of ghcr.io/autobutler-org/schmeide to run. Changing it re-runs the setup script in place and restarts the container; the VM and its data disk are untouched."
  type        = string
  default     = "0.0.1"
}

variable "github_app_id" {
  description = "App ID of the schmeide GitHub App. Not a secret, so it is plain configuration rather than a Key Vault entry."
  type        = string
}

variable "allowed_orgs" {
  description = "Organization or user logins whose repositories may create jobs (SCHMEIDE_ALLOWED_ORGS). schmeide refuses to start with an empty allowlist."
  type        = list(string)

  validation {
    condition     = length(var.allowed_orgs) > 0
    error_message = "allowed_orgs must name at least one login, or schmeide control refuses to start."
  }
}

variable "key_vault_name" {
  description = "Globally unique name of the Key Vault holding the control node's secrets, 3-24 characters."
  type        = string
}

variable "admin_username" {
  description = "Local admin user created on the VM and given the SSH public key."
  type        = string
  default     = "schmeide"
}

variable "admin_ssh_public_key" {
  description = "SSH public key authorized for admin_username. A public key, so committing it is fine."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Source CIDR permitted to reach port 22, or \"*\" for anywhere. Same knob, and the same default, as modules/headscale."
  type        = string
  default     = "*"
}

variable "vm_size" {
  description = "Azure VM SKU. Must match var.vm_architecture."
  type        = string
  default     = "Standard_B2pts_v2"
}

variable "vm_architecture" {
  description = "CPU architecture of vm_size. Selects the Ubuntu image SKU, and the schmeide image must publish this platform."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "amd64"], var.vm_architecture)
    error_message = "vm_architecture must be \"arm64\" or \"amd64\"."
  }
}

variable "data_disk_size_gb" {
  description = "Size of the managed disk holding the JetStream store and Caddy's certificates."
  type        = number
  default     = 32
}

variable "dns_zone_name" {
  description = "Azure DNS zone the control node's hostname lives in. Caddy requests its certificate for <dns_record_name>.<dns_zone_name>."
  type        = string
}

variable "dns_zone_resource_group_name" {
  description = "Resource group holding dns_zone_name."
  type        = string
}

variable "dns_record_name" {
  description = "Zone-relative name of the control node's A record."
  type        = string
  default     = "schmeide"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
