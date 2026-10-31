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
# a record in cloud.autobutler.org. The one public name is argo.errand, in dns.tf.
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

  # One node, always on. It runs AKS addons, Argo CD, and External Secrets.
  # CriticalAddonsOnly keeps every other pod off it, including CI jobs. Argo and
  # External Secrets tolerate that taint in ci-gitops.tf. Changing the flag cycles
  # this pool, so it needs a temporary name. Dsv6 quota is 10 and this node is 2,
  # which leaves room for the temporary node.
  default_node_pool {
    name = "system"
    # DSv5 quota in this subscription cannot be raised. Dsv6 already has room for
    # this one 2-vCPU node.
    vm_size                      = "Standard_D2s_v6"
    node_count                   = 1
    os_disk_size_gb              = 32
    os_disk_type                 = "Managed"
    vnet_subnet_id               = azurerm_subnet.nodes.id
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    # AKS writes these on create. Leaving the block unset plans them back to null.
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  tags = var.tags

  # Azure CLI would create the Network Contributor assignment itself. The identity id
  # referenced above is not a dependency on that assignment, so this depends_on is
  # load-bearing.
  depends_on = [
    azurerm_role_assignment.control_network,
    azurerm_role_assignment.control_argocd_ip,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Two runner pools, one per architecture. Each machine is 4 real cores and 16 GiB.
# Ddsv6 vCPUs are hyperthreads, so the x64 pool is Fadsv7 (SMT off, Turin) and the
# Arm pool is Cobalt, one core per vCPU.
#
# The Arm pool starts at 2 nodes and the autoscaler may add nodes up to 100, which is
# the concurrency target (100 jobs, 400 vCPUs). Two nodes are 8 vCPUs. The Dpdsv6 family
# quota is 10, so a third node (12 vCPUs) cannot be created until that quota is raised.
# The x64 pool starts empty and uses the same ceiling, for the jobs that have to build
# on x64. Two is the Arm floor, not two of each. Fadsv7 quota is also 10.
#
# No node_count. With autoscaling the provider uses min_count as the initial count.
#
# Both sizes have one NVMe and no separate SCSI resource disk. The OS disk is
# ephemeral and consumes that NVMe, so job scratch is local. Changing the x64 size
# or disk type cycles that pool, so it needs a temporary name.
#
# Runner pods select kubernetes.io/arch and ci.autobutler.org/runner. Both pools
# carry the runner taint, so an unselected pod is unschedulable rather than landing
# on the wrong architecture. The system pool's CriticalAddonsOnly taint is what
# keeps a runner off the system node.
#
# Trusted Launch, vTPM, and secure boot stay off. A later guest-kernel mode for
# untrusted jobs requires Trusted Launch to have been left off, and azurerm has no
# argument to set it on these pools, so the default of off is load-bearing. Do not add a
# security profile that turns it on. Privileged DinD is allowed while every job is
# AutoButler's. An Azure Policy add-on would block that, so Azure Policy, Container
# Insights, and the OMS agent are not enabled on the cluster either.
resource "azurerm_kubernetes_cluster_node_pool" "arm" {
  name                  = "arm"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D4pds_v6"
  mode                  = "User"
  vnet_subnet_id        = azurerm_subnet.nodes.id

  auto_scaling_enabled = true
  min_count            = 2
  max_count            = 100

  os_disk_type    = "Ephemeral"
  os_disk_size_gb = 128

  # AKS writes these on create. Leaving the block unset plans them back to null.
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }

  node_labels = {
    "ci.autobutler.org/runner" = "true"
  }

  node_taints = [
    "ci.autobutler.org/runner=true:NoSchedule",
  ]

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "x64" {
  name                  = "x64"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_F4ads_v7"
  mode                  = "User"
  vnet_subnet_id        = azurerm_subnet.nodes.id

  auto_scaling_enabled = true
  min_count            = 0
  # Azure counts every pool's max_count against the pod CIDR, 256 addresses
  # per node. Steady state is 201 nodes, 51456 addresses, inside the 65536 of
  # 10.244.0.0/16. A rotation adds x64temp at the same max, 77056 addresses,
  # which does not fit. Before changing the size or disk type, drop this to 50,
  # apply, rotate, then raise it back.
  max_count = 100

  # 128 GiB fits in the 440 GiB NVMe. Ephemeral placement uses that disk.
  os_disk_type                = "Ephemeral"
  os_disk_size_gb             = 128
  temporary_name_for_rotation = "x64temp"

  # AKS writes these on create. Leaving the block unset plans them back to null.
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }

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
