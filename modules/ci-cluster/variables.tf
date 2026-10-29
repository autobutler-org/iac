variable "resource_group_name" {
  description = "Existing resource group to create the cluster in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for every resource this module creates. The Kubernetes patch pin and the VM sizes were checked in eastus."
  type        = string
  default     = "eastus"
}

variable "dns_zone_name" {
  description = "Azure DNS zone the Argo CD A record is created in. The record name is argo.errand, so this zone must be cloud.autobutler.org."
  type        = string
}

variable "dns_zone_resource_group_name" {
  description = "Resource group of dns_zone_name. The zone is not in the cluster resource group."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource this module manages. The root module passes local.tags; this module does not add its own."
  type        = map(string)
  default     = {}
}
