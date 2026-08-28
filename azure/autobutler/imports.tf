# The quark-headscale resource group was created by hand and is adopted rather than
# created: terraform cannot create a resource group that already exists, and deleting it to
# let terraform recreate it is a pointless risk.
#
# Nothing else in headscale.tf is imported -- the group is empty, so every resource inside
# it is a genuine create.
#
# Delete this file once the import has been applied and state holds the group.

import {
  to = azurerm_resource_group.quark_headscale
  id = "/subscriptions/8add0a4f-6638-4cf3-95bd-cd46ab3ca970/resourceGroups/quark-headscale"
}
