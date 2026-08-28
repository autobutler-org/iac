# These resources predate this repo -- they were created by hand and are being adopted, not
# created. Run `make plan` and confirm the plan is three imports and no changes other than
# the tags noted in main.tf, then apply.
#
# import blocks belong to the configuration, not the module, which is why they live here
# and address the resources through `module.quark`. The IDs themselves are unchanged by the
# module boundary.
#
# Delete this file once the import has been applied and state holds all three resources.
# Leaving it in place is harmless but makes every subsequent plan re-check IDs that are
# already in state.

import {
  to = module.quark.azurerm_resource_group.quark
  id = "/subscriptions/8add0a4f-6638-4cf3-95bd-cd46ab3ca970/resourceGroups/quark"
}

import {
  to = module.quark.azurerm_storage_account.release
  id = "/subscriptions/8add0a4f-6638-4cf3-95bd-cd46ab3ca970/resourceGroups/quark/providers/Microsoft.Storage/storageAccounts/quarkrelease"
}

import {
  to = module.quark.azurerm_storage_container.releases
  id = "/subscriptions/8add0a4f-6638-4cf3-95bd-cd46ab3ca970/resourceGroups/quark/providers/Microsoft.Storage/storageAccounts/quarkrelease/blobServices/default/containers/releases"
}
