variable "location" {
  description = "Azure region holding the quark resources."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group holding the quark release storage account."
  type        = string
  default     = "quark"
}

variable "storage_account_name" {
  description = "Globally unique name of the storage account serving quark release artifacts. Baked into the quark client -- see storage.tf."
  type        = string
  default     = "quarkrelease"
}

variable "container_name" {
  description = "Blob container serving quark release artifacts. Baked into the quark client -- see storage.tf."
  type        = string
  default     = "releases"
}

variable "account_replication_type" {
  description = "Replication type for the release storage account."
  type        = string
  default     = "LRS"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
