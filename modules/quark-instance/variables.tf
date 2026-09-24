variable "name" {
  description = "Name of the container group."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the instance in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for every resource this module creates."
  type        = string
  default     = "eastus"
}

variable "quark_version" {
  description = "Tag of ghcr.io/autobutler-org/quark to run: bare semver, no leading v. Changing it replaces the container group; the data share is untouched."
  type        = string
}

variable "dns_name_label" {
  description = "DNS label for the public IP, giving <label>.<location>.azurecontainer.io. Must be unique within the region. Only the CNAME target; the instance is served on the hostname in dns_zone_name."
  type        = string
}

variable "dns_zone_name" {
  description = "Azure DNS zone the instance's hostname lives in. Caddy requests its certificate for <dns_record_name>.<dns_zone_name>."
  type        = string
}

variable "dns_zone_resource_group_name" {
  description = "Resource group holding dns_zone_name."
  type        = string
}

variable "dns_record_name" {
  description = "Zone-relative name of the instance's CNAME."
  type        = string
  default     = "quark"
}

variable "storage_account_name" {
  description = "Globally unique name of the storage account holding the data share."
  type        = string
}

variable "data_share_quota_gb" {
  description = "Size cap of the share mounted at /var/lib/quark. Standard shares bill for what is used, not the quota."
  type        = number
  default     = 100
}

variable "cpu" {
  description = "vCPUs for the quark container."
  type        = number
  default     = 1
}

variable "memory_gb" {
  description = "Memory in GB for the quark container."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
