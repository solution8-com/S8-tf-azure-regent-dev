# Azure Cognitive Services account dedicated to Cohere Rerank within Azure AI Foundry
# Policy requirement: all Cohere usage must stay inside Global Evolution's tenant
resource "azurerm_cognitive_account" "cohere" {
  name                = "${module.naming.cognitive_account.name_unique}-cohere"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  kind                = "OpenAI"
  sku_name            = "S0"
  tags                = var.tags

  custom_subdomain_name         = "${module.naming.cognitive_account.name_unique}-cohere"
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  # Audit logging and encryption managed by Azure defaults; no customer-managed keys for dev environment
}

# NOTE: As of November 2025, `azurerm_cognitive_deployment` only supports Azure OpenAI models directly.
# Cohere Rerank must be deployed via Azure AI Studio or Azure ML managed endpoints.
# Deployment steps are documented in README.md and DEPLOYMENT_GUIDE.md.
