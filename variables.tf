# Regional constraints: All resources must reside in North Europe unless technically impossible
variable "location" {
  type        = string
  default     = "northeurope"
  description = <<DESCRIPTION
Azure region where the resource should be deployed.
All resources must be in North Europe to satisfy EU data residency requirements.
DESCRIPTION
  nullable    = false
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

# Authentication and access control variables
variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = <<DESCRIPTION
List of IP CIDR ranges allowed to access n8n and Haystack endpoints.
If empty and authentication is not enabled, access will be restricted to Azure services only.
Example: ["1.2.3.4/32", "10.0.0.0/24"]
DESCRIPTION
}

variable "enable_entra_auth" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Enable Azure Entra ID (Azure AD) authentication for n8n and Haystack endpoints.
When enabled, users must authenticate with Microsoft 365/Azure AD credentials.
DESCRIPTION
}

# Secrets - must be provided as Terraform variables, never stored in Git
variable "postgres_admin_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = <<DESCRIPTION
PostgreSQL administrator password. Must be provided at runtime.
If not provided, a random password will be generated.
Example: terraform apply -var="postgres_admin_password=SecurePassword123!"
DESCRIPTION
}

variable "cohere_rerank_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = <<DESCRIPTION
API key for Cohere Rerank v3.5 service in Azure AI Foundry.
Will be automatically generated if using managed deployment.
DESCRIPTION
}

variable "external_openai_endpoint" {
  type        = string
  default     = "https://placeholder.openai.azure.com/"
  description = <<DESCRIPTION
OpenAI-compatible endpoint URL in a separate Azure tenant for LLM generation.
Haystack will use this endpoint for generation calls.
Example: https://your-openai.openai.azure.com/
DESCRIPTION
}

variable "external_openai_api_key" {
  type        = string
  sensitive   = true
  default     = "placeholder-key"
  description = <<DESCRIPTION
API key for the external OpenAI-compatible endpoint.
Must be provided at runtime for Haystack LLM integration.
DESCRIPTION
}

variable "external_openai_deployment_name" {
  type        = string
  default     = "gpt-4"
  description = <<DESCRIPTION
Deployment name of the LLM model at the external OpenAI-compatible endpoint.
DESCRIPTION
}

# Control variable for optional MCP deployment - will be removed per requirements
variable "deploy_mcp" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
DEPRECATED: MCP deployment is prohibited per architecture requirements.
This variable is retained for backward compatibility but should always be false.
DESCRIPTION
}

variable "enable_telemetry" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see https://aka.ms/avm/telemetryinfo.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "Custom tags to apply to the resource."
}
