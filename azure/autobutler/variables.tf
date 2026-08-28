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
