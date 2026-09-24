# A shared module has no backend, so unlike a root module (where the terraform block lives
# in backend.tf) this module's terraform block lives in main.tf. That also gives the module
# the main.tf entrypoint `terraform_standard_module_structure` expects, without splitting
# the resources out of the per-type file they belong in.
#
# The constraints are floors, not pins. A module should not over-constrain its callers; the
# root module in azure/<subscription>/ is where versions actually get pinned.
terraform {
  required_version = ">= 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
  }
}
