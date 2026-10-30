output "quark_resource_group_name" {
  description = "Resource group holding the quark release storage account."
  value       = module.quark.resource_group_name
}

output "quark_storage_account_name" {
  description = "Name of the storage account serving quark release artifacts."
  value       = module.quark.storage_account_name
}

output "quark_container_name" {
  description = "Blob container serving quark release artifacts."
  value       = module.quark.container_name
}

output "quark_blob_endpoint" {
  description = "Blob service endpoint the quark client passes to azblob.NewClientWithNoCredential."
  value       = module.quark.blob_endpoint
}

output "quark_release_base_url" {
  description = "Base URL that quark release artifacts are published under, matching UpdateSource.UpdateUrl() in the quark client."
  value       = module.quark.release_base_url
}

output "quark_headscale_public_ip" {
  description = "Static public IP of the quark headscale VM."
  value       = module.quark_headscale.public_ip_address
}

output "quark_headscale_public_ip_fqdn" {
  description = "Azure-assigned FQDN for the quark headscale public IP, usable as a CNAME target."
  value       = module.quark_headscale.public_ip_fqdn
}

output "quark_headscale_dns_record_required" {
  description = "DNS record an operator must create before certbot can issue a certificate for the quark headscale host."
  value       = module.quark_headscale.dns_record_required
}

output "tailnet_dns_zone_nameservers" {
  description = "NS records to create for the delegated label at Porkbun. Until these exist the zone answers for nobody, and certbot cannot issue a certificate for anything inside it. One-time step; records inside the zone are managed by terraform from then on."
  value       = azurerm_dns_zone.tailnet.name_servers
}

output "tailnet_dns_zone_name" {
  description = "The delegated public DNS zone. Its parent stays at Porkbun."
  value       = azurerm_dns_zone.tailnet.name
}

output "quark_instance_url" {
  description = "Public HTTPS URL of the quark container instance."
  value       = module.quark_instance.url
}

output "quark_instance_data_share" {
  description = "Storage account and Azure Files share holding the quark instance's /var/lib/quark."
  value       = "${module.quark_instance.storage_account_name}/${module.quark_instance.data_share_name}"
}

output "cloud_dns_zone_nameservers" {
  description = "NS records to create for the cloud label at Porkbun. One-time step; until they exist nothing under the zone resolves and the quark instance cannot get a certificate."
  value       = azurerm_dns_zone.cloud.name_servers
}

output "schmeide_control_webhook_url" {
  description = "Webhook URL to set on the schmeide GitHub App."
  value       = module.schmeide_control.webhook_url
}

output "schmeide_control_nats_url" {
  description = "NATS URL schmeide runners connect to."
  value       = module.schmeide_control.nats_url
}

output "schmeide_control_key_vault_name" {
  description = "Key Vault whose webhook-secret, github-app-private-key and runner-tokens secrets a person sets by hand after the first apply."
  value       = module.schmeide_control.key_vault_name
}

output "ci_cluster_name" {
  description = "AKS cluster name. kubectl and, later, Argo CD target this cluster."
  value       = module.ci_cluster.cluster_name
}

output "ci_cluster_id" {
  description = "ARM id of the CI AKS cluster. CI's cluster role assignments are scoped to this, not the subscription."
  value       = module.ci_cluster.cluster_id
}

output "ci_resource_group_name" {
  description = "Resource group the CI cluster, registry, cache, identities, and vault live in."
  value       = module.ci_cluster.resource_group_name
}

output "ci_oidc_issuer_url" {
  description = "OIDC issuer URL of the CI cluster. Federated credentials for workload identity use this as the issuer."
  value       = module.ci_cluster.oidc_issuer_url
}

output "ci_acr_login_server" {
  description = "ACR login server. The kubelet identity can pull. The image identity can push."
  value       = module.ci_cluster.acr_login_server
}

output "ci_cache_container_url" {
  description = "HTTPS URL of the private CI cache container. Runners authenticate with the runner identity."
  value       = module.ci_cluster.cache_container_url
}

output "ci_key_vault_name" {
  description = "CI Key Vault a person writes the Actions GitHub App private key into after apply. Terraform stores no secret value."
  value       = module.ci_cluster.key_vault_name
}

output "ci_key_vault_id" {
  description = "ARM id of the CI Key Vault. A later access policy attaches here. This output is not a secret."
  value       = module.ci_cluster.key_vault_id
}

output "ci_image_identity_client_id" {
  description = "Client id of the identity Quark's CI image workflow uses to push to ACR. It is not a secret. Set it as CI_IMAGE_AZURE_CLIENT_ID on autobutler-org/quark after apply."
  value       = module.ci_cluster.image_identity_client_id
}

output "ci_runner_identity_client_id" {
  description = "Client id of the CI runner workload identity. The runner chart's Helm values take this after the first apply. It is not a secret."
  value       = module.ci_cluster.runner_identity_client_id
}

output "ci_runner_identity_principal_id" {
  description = "Object id of the CI runner workload identity. The cache role assignment and the vault access policy use it."
  value       = module.ci_cluster.runner_identity_principal_id
}

output "ci_argocd_fqdn" {
  description = "Public hostname of the Argo CD UI, argo.errand.cloud.autobutler.org. The A record aliases the reserved public IP."
  value       = module.ci_cluster.argocd_fqdn
}

output "ci_control_plane_identity_principal_id" {
  description = "Object id of the CI control-plane identity. It has Network Contributor on the cluster VNet, which the cluster create waits for."
  value       = module.ci_cluster.control_plane_identity_principal_id
}
