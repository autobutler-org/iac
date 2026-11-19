variable "resource_group_name" {
  description = "Existing resource group to create everything in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for the cluster and everything but the PostgreSQL server. The Kubernetes patch pin and the VM sizes were checked in eastus."
  type        = string
  default     = "eastus"
}

variable "postgres_location" {
  description = "Azure region for the PostgreSQL flexible server. Not location: flexible server provisioning is restricted in eastus for this subscription."
  type        = string
  default     = "centralus"
}

variable "dns_zone_name" {
  description = "Azure DNS zone the factory A record is created in, cloud.autobutler.org."
  type        = string
}

variable "dns_zone_resource_group_name" {
  description = "Resource group of dns_zone_name. The zone is not in the factory resource group."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource this module manages. The root module passes local.tags."
  type        = map(string)
  default     = {}
}
