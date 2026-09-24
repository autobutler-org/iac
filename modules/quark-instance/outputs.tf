output "url" {
  description = "Public HTTPS URL of the quark instance."
  value       = "https://${local.hostname}"
}

output "storage_account_name" {
  description = "Storage account holding the data share."
  value       = azurerm_storage_account.data.name
}

output "data_share_name" {
  description = "Azure Files share mounted at /var/lib/quark. Mount it on another container group to move the instance."
  value       = azurerm_storage_share.quark.name
}
