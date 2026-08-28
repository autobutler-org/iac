terraform {
  # Pinned to the minor. The whole repo is expected to run one terraform version, and CI
  # reading a different one than a developer's desk is a class of bug worth spending a pin
  # to avoid.
  required_version = "~> 1.16"

  # One state file per subscription -- this configuration is the whole of azure/autobutler.
  #
  # State lives in the autobutler subscription, deliberately, for every subscription this
  # repo manages. The backend resolves its storage account independently of the provider
  # below, so a future azure/<other-sub>/ root module points at this same account without
  # any of this changing. That is why the subscription is written out here as a literal
  # instead of following ARM_SUBSCRIPTION_ID: a backend block cannot take variables, and it
  # should not follow the target subscription anyway.
  #
  # The account is created by bootstrap/main.bicep. See bootstrap/README.md.
  #
  # use_azuread_auth: the state account sets allowSharedKeyAccess=false, so there is no
  # account key to look up and `resource_group_name` is deliberately omitted -- that
  # argument exists only to drive the key lookup. Access is RBAC (Storage Blob Data Owner),
  # and state locking is a native blob lease, so there is no separate lock table.
  backend "azurerm" {
    storage_account_name = "stautobutlertfstate"
    container_name       = "tfstate"
    key                  = "azure/autobutler.tfstate"
    use_azuread_auth     = true
    subscription_id      = "8add0a4f-6638-4cf3-95bd-cd46ab3ca970"
    tenant_id            = "1196631e-40d1-42f3-91a4-1c80f49065f8"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}
