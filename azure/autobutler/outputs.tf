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
