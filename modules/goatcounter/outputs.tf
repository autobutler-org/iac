output "url" {
  description = "GoatCounter dashboard. Log in with admin_email and the password the setup script left on the VM."
  value       = "https://${local.hostname}/"
}

output "count_url" {
  description = "Endpoint the websites send their page view beacon to: navigator.sendBeacon(\"<count_url>?p=<host><path>&r=<referrer>\")."
  value       = "https://${local.hostname}/count"
}

output "vm_name" {
  description = "Name of the GoatCounter VM, for az ssh vm."
  value       = azurerm_linux_virtual_machine.this.name
}

output "backup_container_url" {
  description = "Blob container the daily database backups are written to, one gzipped SQLite file per run."
  value       = local.backup_container_url
}
