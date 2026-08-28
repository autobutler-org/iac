resource "azurerm_resource_group" "quark" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# The quark client's self-update path reads this account anonymously. From
# quark/pkg/util/updateutil/updateutil.go:
#
#     client, err = azblob.NewClientWithNoCredential("https://quarkrelease.blob.core.windows.net")
#
# NewClientWithNoCredential sends no Authorization header at all, so public read access is
# not a hardening oversight -- it is the transport. Blobs are laid out as
# releases/quark/<version>/quark_<Os>_<arch>.tar.gz and listed with the prefix "quark/",
# which means the client needs *container-level* anonymous access (list), not just
# blob-level (get). See container_access_type below.
#
# Setting allow_nested_items_to_be_public = false here, or dropping the container down to
# "blob" or "private", breaks self-update for every installed client in the field. It will
# not show up in any test in this repo, and it will not show up until someone tries to
# update. Do not tighten these two settings without shipping a credentialed client first.
resource "azurerm_storage_account" "release" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.quark.name
  location            = azurerm_resource_group.quark.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = true # read the comment above before changing
  shared_access_key_enabled       = true
  public_network_access_enabled   = true

  # network_rules is deliberately absent. The live account allows all networks, and the
  # provider rejects a network_rules block whose default_action is "Allow"; it requires
  # "Deny" plus at least one ip_rules or virtual_network_subnet_ids entry. Omitting the
  # block is how "open to the internet" is expressed, and it is what the anonymous client
  # above requires anyway.

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags

  # Every published quark release artifact lives here, and the clients in the field fetch
  # from this exact hostname -- a destroy is unrecoverable and silently breaks self-update
  # for every installed copy. Removing the account is a deliberate, multi-step act: drop
  # this block in its own commit first.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "releases" {
  name               = var.container_name
  storage_account_id = azurerm_storage_account.release.id

  # "container" (not "blob") because the client lists by prefix rather than fetching a
  # known URL. See the comment on azurerm_storage_account.release.
  container_access_type = "container"

  # Same reasoning as the account above: the container name is part of the URL the clients
  # construct, so losing it is as bad as losing the account.
  lifecycle {
    prevent_destroy = true
  }
}
