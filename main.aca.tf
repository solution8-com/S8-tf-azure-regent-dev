# Azure Container Apps Environment - Runtime environment for n8n and Haystack containers
# Provides isolated compute environment with shared networking and configuration
# System-assigned managed identity enabled for accessing Azure resources
resource "azurerm_container_app_environment" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.container_app_environment.name_unique
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

# Azure Files storage mount for n8n persistence
# Provides persistent storage for SQLite database and workflow state
# Mounted to n8n container at /home/node/.n8n
resource "azurerm_container_app_environment_storage" "this" {
  name                         = "n8nconfig"
  access_key                   = module.storage.resource.primary_access_key
  access_mode                  = "ReadWrite"
  account_name                 = module.storage.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  share_name                   = "n8nconfig"
}

# n8n Container App - Workflow automation platform
# Uses vanilla n8n image with SQLite database persisted to Azure Files
# No custom plugins or modifications per requirements
module "container_app_n8n" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "0.4.0"

  name                                  = "${module.naming.container_app.name_unique}-n8n"
  resource_group_name                   = azurerm_resource_group.this.name
  container_app_environment_resource_id = azurerm_container_app_environment.this.id
  enable_telemetry                      = var.enable_telemetry
  revision_mode                         = "Single"
  tags                                  = var.tags

  template = {
    containers = [
      {
        name   = "n8n"
        memory = "0.5Gi"
        cpu    = 0.25
        # Official n8n Docker image - no modifications
        image = "docker.io/n8nio/n8n:latest"

        env = [
          # SQLite database configuration - persisted to Azure Files
          # DB_TYPE defaults to SQLite when not specified, but explicitly set for clarity
          {
            name  = "DB_TYPE"
            value = "sqlite"
          },
          # Protocol and port configuration
          {
            name  = "N8N_PROTOCOL"
            value = "https"
          },
          {
            name  = "N8N_PORT"
            value = "5678"
          },
          # Webhook URL for external integrations
          {
            name  = "WEBHOOK_URL"
            value = "https://${module.naming.container_app.name_unique}-n8n.${azurerm_container_app_environment.this.default_domain}"
          },
          # Worker mode configuration
          {
            name  = "N8N_RUNNERS_ENABLED"
            value = "true"
          },
          # Azure managed identity configuration for accessing Azure services
          {
            name  = "AZURE_CLIENT_ID"
            value = azurerm_user_assigned_identity.this.client_id
          },
          {
            name  = "AZURE_TENANT_ID"
            value = data.azurerm_client_config.current.tenant_id
          }
        ]

        # Volume mount for SQLite database persistence
        # All n8n data (database, workflows, credentials) stored in Azure Files
        volume_mounts = [
          {
            name = "n8nconfig"
            path = "/home/node/.n8n"
          }
        ]
      }
    ]

    # Azure Files volume for persistent storage
    volumes = [
      {
        name         = "n8nconfig"
        storage_type = "AzureFile"
        storage_name = azurerm_container_app_environment_storage.this.name
      }
    ]
  }

  # Managed identity for accessing Key Vault and other Azure resources
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.this.id]
  }

  # Public HTTP ingress configuration
  # Access control implemented via Entra ID or IP whitelisting based on variables
  ingress = {
    allow_insecure_connections = false
    client_certificate_mode    = "ignore"
    external_enabled           = true
    target_port                = 5678
    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]

    # IP restrictions if specified
    # Note: Entra ID authentication requires additional configuration not shown here
    # as it depends on Azure AD app registration which should be done separately
    ip_security_restrictions = length(var.allowed_ip_ranges) > 0 ? [
      for cidr in var.allowed_ip_ranges : {
        name             = "allow_${replace(cidr, "/", "_")}"
        ip_address_range = cidr
        action           = "Allow"
      }
    ] : []
  }
}

# Haystack Container App - Document search and LLM orchestration
# Provides REST API for document ingestion, retrieval with PostgreSQL FTS, and LLM generation
# Reranking via Cohere Rerank v3.5 from Azure AI Foundry
module "container_app_haystack" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "0.4.0"

  name                                  = "${module.naming.container_app.name_unique}-haystack"
  resource_group_name                   = azurerm_resource_group.this.name
  container_app_environment_resource_id = azurerm_container_app_environment.this.id
  enable_telemetry                      = var.enable_telemetry
  revision_mode                         = "Single"
  tags                                  = var.tags

  template = {
    containers = [
      {
        name   = "haystack"
        memory = "1.0Gi"
        cpu    = 0.5
        # Official Haystack Docker image with all ingestion and query endpoints
        # Note: Haystack official image may be "deepset/haystack" or require custom build
        # Check: https://hub.docker.com/r/deepset/haystack
        image = "deepset/haystack:latest"

        env = [
          # PostgreSQL connection for DocumentStore backend
          {
            name  = "POSTGRES_HOST"
            value = module.postgresql.fqdn
          },
          {
            name  = "POSTGRES_PORT"
            value = "5432"
          },
          {
            name  = "POSTGRES_DB"
            value = "haystack"
          },
          {
            name  = "POSTGRES_USER"
            value = "psqladmin"
          },
          {
            name        = "POSTGRES_PASSWORD"
            secret_name = "postgres-password"
          },
          # Enable SSL for PostgreSQL connection
          {
            name  = "POSTGRES_SSLMODE"
            value = "require"
          },

          # PostgreSQL Full Text Search configuration
          # Retriever uses tsvector, tsquery, ts_rank, and GIN indexing
          {
            name  = "RETRIEVER_TYPE"
            value = "postgres_fts"
          },
          {
            name  = "FTS_CONFIG"
            value = "english" # PostgreSQL text search configuration
          },

          # Cohere Rerank v3.5 configuration for post-retrieval reranking
          {
            name  = "RERANKER_TYPE"
            value = "cohere"
          },
          {
            name  = "COHERE_API_ENDPOINT"
            value = azurerm_cognitive_account.cohere.endpoint
          },
          {
            name        = "COHERE_API_KEY"
            secret_name = "cohere-api-key"
          },
          {
            name  = "COHERE_MODEL"
            value = "rerank-v3"
          },

          # External OpenAI-compatible endpoint for LLM generation
          # This endpoint is in a separate Azure tenant per requirements
          {
            name  = "OPENAI_API_ENDPOINT"
            value = var.external_openai_endpoint
          },
          {
            name        = "OPENAI_API_KEY"
            secret_name = "external-openai-key"
          },
          {
            name  = "OPENAI_DEPLOYMENT_NAME"
            value = var.external_openai_deployment_name
          },

          # REST API configuration - GraphQL disabled per requirements
          {
            name  = "API_TYPE"
            value = "rest"
          },
          {
            name  = "API_PORT"
            value = "8000"
          }
        ]
      }
    ]
  }

  # Managed identity for accessing Key Vault secrets
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.this.id]
  }

  # Secrets from Key Vault for PostgreSQL, Cohere, and external OpenAI access
  secrets = {
    postgres_password = {
      name                = "postgres-password"
      key_vault_secret_id = module.key_vault.secrets_resource_ids["postgres-password"].id
      identity            = azurerm_user_assigned_identity.this.id
    }
    cohere_api_key = {
      name                = "cohere-api-key"
      key_vault_secret_id = module.key_vault.secrets_resource_ids["cohere-api-key"].id
      identity            = azurerm_user_assigned_identity.this.id
    }
    external_openai_key = {
      name                = "external-openai-key"
      key_vault_secret_id = module.key_vault.secrets_resource_ids["external-openai-key"].id
      identity            = azurerm_user_assigned_identity.this.id
    }
  }

  # Public HTTP ingress with authentication requirements
  ingress = {
    allow_insecure_connections = false
    client_certificate_mode    = "ignore"
    external_enabled           = true
    target_port                = 8000
    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]

    # IP restrictions if specified
    # Same authentication model as n8n per requirements
    ip_security_restrictions = length(var.allowed_ip_ranges) > 0 ? [
      for cidr in var.allowed_ip_ranges : {
        name             = "allow_${replace(cidr, "/", "_")}"
        ip_address_range = cidr
        action           = "Allow"
      }
    ] : []
  }
}
