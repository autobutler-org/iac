variable "name_prefix" {
  description = "Prefix for every resource this module creates. The VM takes this name verbatim; the rest append a suffix (-vnet, -pip, -nsg, -nic, -osdisk). Also the public IP's DNS label, so it must be unique within the region."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the GoatCounter resources in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for every resource this module creates."
  type        = string
  default     = "eastus"
}

variable "goatcounter_version" {
  description = "GoatCounter release tag to run, e.g. v2.7.0. The setup script downloads goatcounter-<version>-linux-<vm_architecture>.gz from github.com/arp242/goatcounter/releases. Changing it re-runs the setup script in place, which backs the database up beside itself, swaps the binary and restarts with -automigrate. Move goatcounter_sha256 with it."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.goatcounter_version))
    error_message = "goatcounter_version must be a release tag such as v2.7.0."
  }
}

variable "goatcounter_sha256" {
  description = "SHA-256 of the goatcounter-<goatcounter_version>-linux-<vm_architecture>.gz release asset. GoatCounter publishes no checksum file, so this is recorded when the version is chosen; the setup script refuses to install a download that does not match. It is per architecture, so changing vm_architecture changes it too."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.goatcounter_sha256))
    error_message = "goatcounter_sha256 must be 64 lowercase hex characters."
  }
}

variable "admin_email" {
  description = "Email of the GoatCounter admin user the setup script creates with the site. It is the login name on the dashboard. Its generated password is on the VM; see the module README."
  type        = string
}

variable "admin_username" {
  description = "Local admin user created on the VM and given the SSH public key."
  type        = string
  default     = "goatcounter-admin"
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
  description = "CPU architecture of vm_size. Selects the Ubuntu image SKU and the GoatCounter release asset, so it cannot drift from the size."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "amd64"], var.vm_architecture)
    error_message = "vm_architecture must be \"arm64\" or \"amd64\"."
  }
}

variable "storage_account_name" {
  description = "Globally unique name of the storage account holding the database backups, 3-24 lowercase letters and digits."
  type        = string
}

variable "backup_retention_days" {
  description = "Days a daily backup is kept before the lifecycle rule deletes it. At least 30, because the account is in the Cool tier and a blob deleted sooner is billed as if kept 30 days."
  type        = number
  default     = 90

  validation {
    condition     = var.backup_retention_days >= 30
    error_message = "backup_retention_days must be at least 30."
  }
}

variable "dns_zone_name" {
  description = "Azure DNS zone GoatCounter's hostname lives in. The site, and its certificate, are for <dns_record_name>.<dns_zone_name>."
  type        = string
}

variable "dns_zone_resource_group_name" {
  description = "Resource group holding dns_zone_name."
  type        = string
}

variable "dns_record_name" {
  description = "Zone-relative name of GoatCounter's A record."
  type        = string
  default     = "stats"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
