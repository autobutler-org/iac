output "public_ip_address" {
  description = "Static public IP of the headscale VM. The A record for headscale_domain must point here."
  value       = azurerm_public_ip.this.ip_address
}

output "public_ip_fqdn" {
  description = "Azure-assigned FQDN for the public IP (<label>.<region>.cloudapp.azure.com). Usable as a CNAME target, and as a way in before the real DNS record exists."
  value       = azurerm_public_ip.this.fqdn
}

output "dns_record_required" {
  description = "The DNS record an operator must create by hand, or a note that terraform owns it. Empty-handed guessing about which is the case is how the wrong record gets created twice."
  value = var.dns_zone_name == null ? (
    "${var.headscale_domain}. IN A ${azurerm_public_ip.this.ip_address}"
    ) : (
    "none -- managed by terraform as an alias record in ${var.dns_zone_name}"
  )
}

output "vm_id" {
  description = "Resource ID of the headscale virtual machine."
  value       = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  description = "Name of the headscale virtual machine."
  value       = azurerm_linux_virtual_machine.this.name
}

output "principal_id" {
  description = "Object ID of the VM's system-assigned managed identity, for granting it access to other Azure resources."
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}
