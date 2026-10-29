variable "resource_group_name" {
  description = "Existing resource group to create the cluster in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for every resource this module creates. The Kubernetes patch pin and the VM sizes were checked in eastus."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags applied to every resource this module manages. The root module passes local.tags; this module does not add its own."
  type        = map(string)
  default     = {}
}
