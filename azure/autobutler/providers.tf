# subscription_id is not set here on purpose. It comes from ARM_SUBSCRIPTION_ID, which the
# Makefile derives from the `azure/<subscription>/` directory this root module lives in --
# so the directory name is the single source of truth for which subscription gets touched,
# and no subscription GUID has to be kept in sync across root modules.
#
# Running terraform directly, outside `make`, needs it exported:
#   export ARM_SUBSCRIPTION_ID=$(az account show --subscription autobutler --query id -o tsv)
provider "azurerm" {
  features {}
}
