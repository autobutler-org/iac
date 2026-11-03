# Tenant move, 2026-11: the subscription went from directory 1196631e-... to
# 76a63a4b-... (autobutler.onmicrosoft.com). replace_triggered_by does not fire when its
# trigger is first created, so each tenant trigger is imported holding the OLD tenant.
# The plan then updates it to the current tenant, and that update replaces every
# user-assigned identity. Remove both blocks once this has been applied.
import {
  to = terraform_data.tenant
  id = "1196631e-40d1-42f3-91a4-1c80f49065f8"
}

import {
  to = module.ci_cluster.terraform_data.tenant
  id = "1196631e-40d1-42f3-91a4-1c80f49065f8"
}
