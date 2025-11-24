# Key Vault for secure secret storage
# Stores PostgreSQL password, Cohere API key, and external OpenAI credentials
# All secrets are referenced by container apps via managed identity
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.0"

  location                      = azurerm_resource_group.this.location
  name                          = module.naming.key_vault.name_unique
  resource_group_name           = azurerm_resource_group.this.name
  enable_telemetry              = var.enable_telemetry
  public_network_access_enabled = true # No VNet integration per requirements
  tags                          = var.tags
  tenant_id                     = data.azurerm_client_config.current.tenant_id

  # Secret definitions - actual values populated below
  secrets = {
    postgres-password = {
      name = "postgres-password"
    }
    cohere-api-key = {
      name = "cohere-api-key"
    }
    external-openai-key = {
      name = "external-openai-key"
    }
  }

  # Secret values - sourced from variables or generated passwords
  secrets_value = {
    postgres-password   = var.postgres_admin_password != "" ? var.postgres_admin_password : random_password.postgres_admin_password.result
    cohere-api-key      = var.cohere_rerank_api_key
    external-openai-key = var.external_openai_api_key
  }

  # RBAC assignments for Key Vault access
  # Deployment user needs admin access, container apps need secrets read access
  role_assignments = {
    deployment_user_kv_admin = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    container_app_kv_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = azurerm_user_assigned_identity.this.principal_id
    }
  }

  # Wait for RBAC propagation before secret operations
  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }

  # Network ACLs - allow Azure services and optionally specific IP ranges
  # No private endpoints per requirements
  network_acls = {
    bypass         = "AzureServices"
    default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    ip_rules       = var.allowed_ip_ranges
  }
}
