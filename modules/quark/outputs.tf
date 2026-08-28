output "resource_group_name" {
  description = "Resource group holding the quark release storage account."
  value       = azurerm_resource_group.quark.name
}

output "storage_account_name" {
  description = "Name of the storage account serving quark release artifacts."
  value       = azurerm_storage_account.release.name
}

output "container_name" {
  description = "Blob container serving quark release artifacts."
  value       = azurerm_storage_container.releases.name
}

output "blob_endpoint" {
  description = "Blob service endpoint the quark client passes to azblob.NewClientWithNoCredential."
  value       = azurerm_storage_account.release.primary_blob_endpoint
}

output "release_base_url" {
  description = "Base URL that quark release artifacts are published under, matching UpdateSource.UpdateUrl() in the quark client."
  value       = "${azurerm_storage_account.release.primary_blob_endpoint}${azurerm_storage_container.releases.name}/quark"
}
