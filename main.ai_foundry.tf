# Azure AI Foundry Hub and Project for Cohere Rerank v3.5
# Provides managed AI model deployment infrastructure in North Europe
# Cohere Rerank v3.5 is used by Haystack for document reranking after retrieval

# Note: Azure AI Foundry resources may not be available in all regions
# If North Europe is not supported, the closest EU region should be used
# Check: https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models

# AI Foundry Hub - Container for AI projects and shared resources
# Uses Azure Cognitive Services account configured for OpenAI
# Note: "AIServices" kind is not supported in the current provider version
# Using "OpenAI" as the kind, which provides access to Azure OpenAI capabilities
# This can be extended to include Cohere and other models via Azure AI Studio
resource "azurerm_cognitive_account" "ai_hub" {
  name                = "${module.naming.cognitive_account.name_unique}-hub"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  kind                = "OpenAI"
  sku_name            = "S0"
  tags                = var.tags

  # Managed identity for accessing other Azure resources
  identity {
    type = "SystemAssigned"
  }

  # No VNet integration per requirements
  public_network_access_enabled = true
}

# Cohere Rerank v3.5 deployment
# IMPORTANT: As of December 2024, Cohere models in Azure AI Foundry may require
# deployment through Azure AI Studio or Azure ML managed endpoints rather than
# direct Terraform resources. The azurerm_cognitive_deployment resource is primarily
# for Azure OpenAI models.
#
# For a fully automated deployment without manual steps, two approaches are available:
#
# 1. Use Azure OpenAI Service with a model that supports reranking (if available)
# 2. Use the Cohere API directly (external to Azure, via their cloud endpoint)
#
# The resource below is commented out as it may not work for Cohere models.
# If Cohere becomes available via Terraform, uncomment and adjust as needed.
#
# resource "azurerm_cognitive_deployment" "cohere_rerank" {
#   name                 = "cohere-rerank-v3"
#   cognitive_account_id = azurerm_cognitive_account.ai_hub.id
#
#   model {
#     format  = "OpenAI"
#     name    = "cohere-rerank-v3"
#     version = "3.5"
#   }
#
#   scale {
#     type     = "Standard"
#     capacity = 1
#   }
# }

# For now, Haystack will be configured to use the AI Services endpoint
# with the Cohere API key provided via variable/Key Vault
# This assumes Cohere models are accessible via the AIServices kind account
# or that the cohere_rerank_api_key variable contains a direct Cohere cloud API key

# Note: Outputs for AI Foundry endpoints are defined in outputs.tf
