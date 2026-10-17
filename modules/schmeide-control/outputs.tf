output "webhook_url" {
  description = "Webhook URL to set on the schmeide GitHub App."
  value       = "https://${local.hostname}/webhook"
}

output "nats_url" {
  description = "NATS URL runners connect to."
  value       = "tls://${local.hostname}:4222"
}

output "key_vault_name" {
  description = "Key Vault holding the webhook-secret, github-app-private-key and runner-tokens secrets, which a person sets by hand."
  value       = azurerm_key_vault.this.name
}
