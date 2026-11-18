# Dedicated to factory. Agent sessions run code nobody reviewed, so they get their own
# control plane, node pools and secret store rather than a node pool beside the CI
# runners, Argo CD and the GitHub App key in autobutler-ci.
#
# Free tier, Entra-only, workload identity, Cilium overlay and a public API server with
# no authorized ranges, for the reasons in modules/ci-cluster/cluster.tf.
resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = local.dns_prefix
  kubernetes_version  = local.kubernetes_version
  sku_tier            = "Free"

  # Not the default MC_ name, for the tenant-move reason in modules/ci-cluster.
  node_resource_group = "${var.resource_group_name}-nodes"

  automatic_upgrade_channel = "patch"

  local_account_disabled    = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control.id]
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  node_provisioning_profile {
    mode               = "Manual"
    default_node_pools = "None"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.245.0.0/16"
    dns_service_ip      = "10.245.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"

    # Advanced Container Networking Services security: Cilium FQDN network policy, so
    # worker pods can be held to cluster DNS, the factory Service, GitHub and the model
    # API. Billed per node-hour. Observability stays off; managed Prometheus below
    # covers metrics.
    advanced_networking {
      security_enabled      = true
      observability_enabled = false
    }

    load_balancer_profile {
      outbound_ip_address_ids = [azurerm_public_ip.egress.id]
    }
  }

  # Managed Prometheus: the ama-metrics add-on scrapes the cluster and ships to the Azure
  # Monitor workspace through the data collection rule in monitor.tf. It also serves
  # PodMonitor and ServiceMonitor in azmonitoring.coreos.com/v1, which is how the
  # factory chart marks its pods for scraping.
  monitor_metrics {}

  # Not tainted CriticalAddonsOnly, unlike the CI system pool. The factory server and
  # External Secrets run here; only agent workers go to the workers pool. Grows to a second node if they do not fit in one. Dsv6 quota
  # in eastus is 10 vCPUs with 2 used by the CI system node: 4 here at max, plus 2 for
  # the rotation node, fits.
  default_node_pool {
    name                        = "system"
    vm_size                     = "Standard_D2s_v6"
    auto_scaling_enabled        = true
    min_count                   = 1
    max_count                   = 2
    os_disk_size_gb             = 32
    os_disk_type                = "Managed"
    vnet_subnet_id              = azurerm_subnet.nodes.id
    temporary_name_for_rotation = "systemtmp"
    tags                        = var.tags

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.control_network,
    azurerm_role_assignment.control_ingress_ip,
    azurerm_role_assignment.control_egress_ip,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Agent workers: Kubernetes Jobs in factory-workers. Only pods that tolerate the taint
# land here, and only workers do.
#
# Standard_D4pds_v6: 4 Cobalt cores, 16 GiB, the CI Arm runner size. The 128 GiB OS
# disk is ephemeral, on the node's local NVMe, and holds every clone and build on the
# node. Dpdsv6 quota in eastus is 400 vCPUs, so no request is needed. Starts empty and
# grows to 3 nodes.
#
# Agent Substrate, if adopted later, needs no other node setup for gVisor: atelet
# fetches runsc itself. It expects the taint ate.dev/sandboxClass=gvisor instead of
# this one, which is a pool rotation.
resource "azurerm_kubernetes_cluster_node_pool" "workers" {
  name                  = "workers"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D4pds_v6"
  mode                  = "User"
  vnet_subnet_id        = azurerm_subnet.nodes.id

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = 3

  os_disk_type                = "Ephemeral"
  os_disk_size_gb             = 128
  temporary_name_for_rotation = "workerstmp"

  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }

  node_labels = {
    "factory.autobutler.org/workers" = "true"
  }

  node_taints = [
    "factory.autobutler.org/workers=true:NoSchedule",
  ]

  tags = var.tags
}

# What the Helm provider in the root module needs: Cluster User for a kubelogin token,
# RBAC Cluster Admin to install External Secrets.
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

# The factory deploy. Cluster Admin rather than a namespace-scoped role: the chart
# creates RBAC and resources in factory-workers as well as factory, and the
# bootstrap role-assignment condition allows only the six roles in
# bootstrap/github-oidc.bash. This cluster runs nothing but factory.
resource "azurerm_role_assignment" "deploy_cluster_user" {
  scope                            = azurerm_kubernetes_cluster.this.id
  role_definition_name             = "Azure Kubernetes Service Cluster User Role"
  principal_id                     = azurerm_user_assigned_identity.deploy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "deploy_cluster_admin" {
  scope                            = azurerm_kubernetes_cluster.this.id
  role_definition_name             = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id                     = azurerm_user_assigned_identity.deploy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
