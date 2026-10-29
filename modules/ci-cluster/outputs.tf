output "cluster_name" {
  description = "AKS cluster name. kubectl and, later, Argo CD target this cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "ARM id of the AKS cluster. CI's cluster role assignments are scoped to this, not the subscription."
  value       = azurerm_kubernetes_cluster.this.id
}

output "resource_group_name" {
  description = "Resource group the cluster, registry, cache, identities, and vault live in. The caller created it."
  value       = var.resource_group_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster. Federated credentials for workload identity use this as the issuer."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "acr_login_server" {
  description = "ACR login server the runner chart pulls from. The kubelet identity can pull; this module grants no push."
  value       = azurerm_container_registry.this.login_server
}

output "cache_container_url" {
  description = "HTTPS URL of the private cache container. Runners authenticate with the runner identity; the container is not anonymous."
  value       = "${azurerm_storage_account.cache.primary_blob_endpoint}${azurerm_storage_container.cache.name}"
}

output "key_vault_name" {
  description = "Key Vault a person writes the Actions GitHub App private key into after apply. Terraform stores no secret value."
  value       = azurerm_key_vault.this.name
}

output "key_vault_id" {
  description = "ARM id of the CI Key Vault. A later access policy, such as External Secrets, attaches here without this module creating a secret."
  value       = azurerm_key_vault.this.id
}

output "runner_identity_client_id" {
  description = "Client id of the runner workload identity. The runner chart's Helm values take this. It is not a secret."
  value       = azurerm_user_assigned_identity.runner.client_id
}

output "runner_identity_principal_id" {
  description = "Object id of the runner workload identity. The Key Vault access policy and the cache role assignment use it."
  value       = azurerm_user_assigned_identity.runner.principal_id
}

output "argocd_public_ip_name" {
  description = "Name of the static public IP reserved for Argo CD. The Argo Service attaches this address by name. It lives in resource_group_name, not the node resource group."
  value       = azurerm_public_ip.argocd.name
}

output "argocd_fqdn" {
  description = "Public hostname of the Argo CD UI. The A record aliases the reserved public IP."
  value       = "${azurerm_dns_a_record.argocd.name}.${azurerm_dns_a_record.argocd.zone_name}"
}

output "control_plane_identity_principal_id" {
  description = "Object id of the control-plane identity. It has Network Contributor on the cluster VNet, which the cluster create waits for."
  value       = azurerm_user_assigned_identity.control.principal_id
}

output "cluster_host" {
  description = "Kubernetes API host for a Helm provider. The public API address, not a client credential. Do not pair it with a client certificate: local accounts are disabled, and client_certificate and client_key are not outputs."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate for a Helm provider. The azurerm provider marks the attribute sensitive. It is not a client credential."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}
