output "cluster_name" {
  description = "AKS cluster name. az aks get-credentials takes this."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "ARM id of the factory AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "resource_group_name" {
  description = "Resource group the cluster, server, vault, storage and identities live in. The caller created it."
  value       = var.resource_group_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster. Federated credentials for workload identity use this as the issuer."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "cluster_host" {
  description = "Kubernetes API host for a Helm provider. Not a client credential."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate for a Helm provider. The azurerm provider marks it sensitive. Not a client credential."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "key_vault_name" {
  description = "Factory Key Vault. Holds the database URLs a person writes after apply, and postgres-admin-password while the managed server is enabled."
  value       = azurerm_key_vault.this.name
}

output "key_vault_id" {
  description = "ARM id of the factory Key Vault, where the External Secrets access policy attaches."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "Vault URI for the External Secrets ClusterSecretStore."
  value       = azurerm_key_vault.this.vault_uri
}

output "postgres_fqdn" {
  description = "Hostname of the PostgreSQL flexible server. TLS is required. Null while postgres_enabled is off."
  value       = one(azurerm_postgresql_flexible_server.this[*].fqdn)
}

output "postgres_admin_login" {
  description = "Admin login of the PostgreSQL server. The password is the postgres-admin-password secret in the vault. Null while postgres_enabled is off."
  value       = one(azurerm_postgresql_flexible_server.this[*].administrator_login)
}

output "fqdn" {
  description = "Public hostname of the factory server. The A record aliases the reserved ingress address."
  value       = "${azurerm_dns_a_record.factory.name}.${azurerm_dns_a_record.factory.zone_name}"
}

output "ingress_public_ip_name" {
  description = "Name of the static address the factory Service attaches. It lives in resource_group_name, not the node resource group."
  value       = azurerm_public_ip.ingress.name
}

output "egress_ip_address" {
  description = "The one address the cluster's outbound traffic leaves from. The PostgreSQL firewall admits it."
  value       = azurerm_public_ip.egress.ip_address
}

output "snapshot_container_url" {
  description = "HTTPS URL of the private Substrate snapshot container. Entra-only; no account keys."
  value       = "${azurerm_storage_account.snapshots.primary_blob_endpoint}${azurerm_storage_container.snapshots.name}"
}

output "deploy_identity_client_id" {
  description = "Client id autobutler-org/factory's deploy workflow logs in with from its production environment. Not a secret."
  value       = azurerm_user_assigned_identity.deploy.client_id
}

output "grafana_url" {
  description = "Azure Managed Grafana endpoint. Sign in with Entra; a person needs a Grafana role on the instance."
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "monitor_workspace_query_endpoint" {
  description = "PromQL query endpoint of the Azure Monitor workspace. Callers authenticate with Entra and need Monitoring Data Reader."
  value       = azurerm_monitor_workspace.this.query_endpoint
}
