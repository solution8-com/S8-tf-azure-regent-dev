# Azure Naming module - provides consistent, unique names for all Azure resources
# This ensures resource names meet Azure naming requirements and avoid conflicts
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.0"
}

# Resource Group - Single container for all infrastructure resources in North Europe
# All resources in this deployment are provisioned within this single resource group
resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming.resource_group.name_unique
  tags     = var.tags
}

# Current Azure client configuration - used to retrieve tenant and subscription details
# Required for configuring managed identities and RBAC assignments
data "azurerm_client_config" "current" {}

# User-assigned managed identity - used by container apps to access Azure resources
# This identity is granted access to Key Vault secrets and other Azure services
# System-assigned identities are avoided to maintain explicit security boundaries
resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.user_assigned_identity.name_unique
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}
