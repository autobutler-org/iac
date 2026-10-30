# AutoButler's CI cluster. Terraform owns the cluster, the registry, the cache, the
# identities, and the vault. The runner chart is not in this repo. Argo CD, not this
# file, is what will apply it.
#
# BEFORE THE FIRST APPLY, someone who can assign roles re-runs
# ./bootstrap/github-oidc.bash create. Contributor cannot write role assignments, and
# the module's first role assignment fails until that script has granted a constrained
# Role Based Access Control Administrator. modules/ci-cluster/README.md has the rest.
# Apply happens from main via CI. Do not apply this from a laptop.
resource "azurerm_resource_group" "autobutler_ci" {
  name     = "autobutler-ci"
  location = var.location
  tags     = local.tags
}

module "ci_cluster" {
  source = "../../modules/ci-cluster"

  resource_group_name = azurerm_resource_group.autobutler_ci.name
  location            = var.location
  tags                = local.tags

  dns_zone_name                = azurerm_dns_zone.cloud.name
  dns_zone_resource_group_name = azurerm_resource_group.dns.name
}
