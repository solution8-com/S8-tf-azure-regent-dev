# Terraform configuration for minimal Azure infrastructure deployment
# Supports Haystack service, n8n workflow automation, PostgreSQL with FTS, 
# and Azure AI Foundry with Cohere Rerank v3.5
terraform {
  required_version = ">= 1.8, < 2.0"

  # Remote state stored in Azure Blob Storage
  # The backend configuration must be provided at init time or via a backend config file
  # Example: terraform init -backend-config="backend.hcl"
  # Uncomment and configure before deploying to production
  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "tfstatestorage"
  #   container_name       = "tfstate"
  #   key                  = "dev.terraform.tfstate"
  # }

  required_providers {
    # Azure Resource Manager provider - pessimistically pinned to major version 4
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # Random provider for generating secure passwords
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
