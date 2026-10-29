# The apply identity, looked up by the app registration name bootstrap/github-oidc.bash
# creates. data.azurerm_client_config would be whoever ran terraform, and a local plan
# would then grant that person cluster admin. The object id is the service principal.
data "azuread_service_principal" "github_actions" {
  display_name = local.github_actions_app_name
}

# Free, not Standard. The research cost table priced AKS Standard for a ten-node
# always-on sketch. This cluster scales the runner pool to zero and does not need the
# uptime SLA. The system pool is the always-on cost, and it does not run jobs.
#
# The API server is public and has no authorized IP ranges. GitHub-hosted Actions
# runners have no stable egress, and the Helm provider has to reach the API from those
# runners. Entra is the lock, which is why local accounts are off. Do not restrict this
# to an operator's home IP.
#
# dns_prefix is the Azure-managed API hostname (<prefix>.<region>.azmk8s.io). It is not
# a record in cloud.autobutler.org. Nothing on this cluster accepts inbound connections,
# so this module creates no DNS record and no public IP for one.
resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = local.dns_prefix
  kubernetes_version  = local.kubernetes_version
  sku_tier            = "Free"

  # Holds the minor at 1.36 while Azure applies later 1.36 patches. See the local.
  automatic_upgrade_channel = "patch"

  local_account_disabled    = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # linux_profile is omitted on purpose. azurerm 5.11 makes it optional, and with local
  # accounts disabled there is no local admin for an SSH key to log in as. No private
  # key is generated, and the operator public key is not copied in for a login that
  # cannot succeed.

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control.id]
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  # azurerm 5.11 requires this block. Manual, and no automatic default pools: Auto would
  # let AKS create node pools this module does not describe, which fights the system
  # pool and the scale-to-zero runner pool.
  node_provisioning_profile {
    mode               = "Manual"
    default_node_pools = "None"
  }

  # Azure CNI overlay with Cilium for the dataplane and for network policy. Pods are
  # not allocated from the node subnet. The provider accepts this combination.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.245.0.0/16"
    dns_service_ip      = "10.245.0.10"
  }

  # One node, always on. It runs cluster addons and, later, Argo CD and External
  # Secrets. It does not run CI jobs: the runner pool is tainted, so those pods cannot
  # land here. only_critical_addons_enabled stays off, because turning it on would leave
  # Argo and External Secrets with nowhere to schedule.
  default_node_pool {
    name            = "system"
    vm_size         = "Standard_D2s_v5"
    node_count      = 1
    os_disk_size_gb = 32
    os_disk_type    = "Managed"
    vnet_subnet_id  = azurerm_subnet.nodes.id
    tags            = var.tags
  }

  tags = var.tags

  # Azure CLI would create the Network Contributor assignment itself. The identity id
  # referenced above is not a dependency on that assignment, so this depends_on is
  # load-bearing.
  depends_on = [azurerm_role_assignment.control_network]

  lifecycle {
    prevent_destroy = true
  }
}

# Scale to zero. min_count 0 with autoscaling, and no node_count: the provider treats an
# omitted count as 0 and uses min_count as the initial count, so the pool is created
# empty. Standard_D4ds_v6 is 4 vCPU and 16 GiB, which is enough for a normal AutoButler
# job without keeping a D8 warm.
#
# Ephemeral OS on the only local disk. This SKU has no SCSI resource disk
# (MaxResourceVolumeMB is 0) and one 220 GiB NVMe (NvmeDiskSizeInMiB 225280), and
# SupportedEphemeralOSDiskPlacements is NvmeDisk. 128 GiB fits. The ephemeral OS consumes
# that NVMe, which is acceptable because scale-to-zero throws the warm cache away.
#
# The taint keeps system pods on the system pool. Without it, a scale-up would be a
# legal home for CoreDNS and the pool could not return to zero.
#
# Trusted Launch, vTPM, and secure boot stay off. A later guest-kernel mode for
# untrusted jobs requires Trusted Launch to have been left off, and azurerm has no
# argument to set it on this pool, so the default of off is load-bearing. Do not add a
# security profile that turns it on. Privileged DinD is allowed while every job is
# AutoButler's. An Azure Policy add-on would block that, so Azure Policy, Container
# Insights, and the OMS agent are not enabled on the cluster either.
resource "azurerm_kubernetes_cluster_node_pool" "runners" {
  name                  = "runners"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D4ds_v6"
  mode                  = "User"
  vnet_subnet_id        = azurerm_subnet.nodes.id

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = 3

  os_disk_type    = "Ephemeral"
  os_disk_size_gb = 128

  node_labels = {
    "ci.autobutler.org/runner" = "true"
  }

  node_taints = [
    "ci.autobutler.org/runner=true:NoSchedule",
  ]

  tags = var.tags
}

# Cluster User is what kubelogin needs to get an API token. RBAC Cluster Admin is what
# CI needs to install Argo and the runner chart. Both are scoped to this cluster.
# principal_type is set because the bootstrap grant that lets CI create these
# assignments is itself constrained on principal type. skip_service_principal_aad_check
# stays off: this principal already exists, and the data source just read it.
resource "azurerm_role_assignment" "github_actions_cluster_user" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azuread_service_principal.github_actions.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_actions_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azuread_service_principal.github_actions.object_id
  principal_type       = "ServicePrincipal"
}
