# Outputs for accessing deployed services and retrieving connection information

# n8n endpoint URL
output "n8n_fqdn_url" {
  description = "HTTPS URL for accessing the n8n workflow automation interface"
  value       = module.container_app_n8n.fqdn_url
}

# Haystack endpoint URL
output "haystack_fqdn_url" {
  description = "HTTPS URL for accessing the Haystack REST API"
  value       = module.container_app_haystack.fqdn_url
}

# PostgreSQL connection information
output "postgresql_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server for Haystack DocumentStore"
  value       = module.postgresql.fqdn
}

output "postgresql_database" {
  description = "Database name for Haystack DocumentStore"
  value       = "haystack"
}

# Cohere Rerank configuration
output "cohere_rerank_endpoint" {
  description = "Azure AI Foundry endpoint for Cohere Rerank v3.5"
  value       = azurerm_cognitive_account.ai_hub.endpoint
}

# Key Vault information for secret access
output "key_vault_uri" {
  description = "URI of the Key Vault containing all secrets"
  value       = module.key_vault.resource_id
}

# Resource Group
output "resource_group_name" {
  description = "Name of the resource group containing all infrastructure"
  value       = azurerm_resource_group.this.name
}

output "resource_group_location" {
  description = "Location of the resource group (should be North Europe)"
  value       = azurerm_resource_group.this.location
}
