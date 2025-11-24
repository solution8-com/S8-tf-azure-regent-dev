# Random password generator for PostgreSQL administrator
# Used to create a secure password that meets Azure PostgreSQL requirements
resource "random_password" "postgres_admin_password" {
  length           = 16
  override_special = "_%@"
  special          = true
}

# PostgreSQL Flexible Server - Backend for Haystack DocumentStore
# Configured with Full Text Search (FTS) capabilities using tsvector, tsquery, and GIN indexing
# This provides Supabase-compatible PostgreSQL FTS semantics for Haystack
module "postgresql" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "0.1.4"

  location            = azurerm_resource_group.this.location
  name                = module.naming.postgresql_server.name_unique
  resource_group_name = azurerm_resource_group.this.name

  # Admin credentials - password from variable or generated random password
  administrator_login    = "psqladmin"
  administrator_password = var.postgres_admin_password != "" ? var.postgres_admin_password : random_password.postgres_admin_password.result

  enable_telemetry              = var.enable_telemetry
  high_availability             = null              # Not required for development
  public_network_access_enabled = true              # Simplified networking per requirements
  server_version                = 16                # Latest stable PostgreSQL version
  sku_name                      = "B_Standard_B1ms" # Minimal SKU for development
  tags                          = var.tags
  zone                          = 1

  # Haystack database with UTF8 encoding for proper text search support
  # n8n database retained for backward compatibility but n8n will use SQLite
  databases = {
    haystack = {
      charset   = "UTF8"
      collation = "en_US.utf8"
      name      = "haystack"
    }
  }

  # Firewall rules - Container Apps Environment and optional admin IP ranges
  # Azure service access enabled via special 0.0.0.0 rule
  # No VNet integration or private endpoints per requirements
  firewall_rules = merge(
    {
      azure_services = {
        name             = "azure_services"
        end_ip_address   = "0.0.0.0"
        start_ip_address = "0.0.0.0"
      }
    },
    # Add admin IP ranges if specified
    { for idx, cidr in var.allowed_ip_ranges : "admin_ip_${idx}" => {
      name             = "admin_ip_${idx}"
      start_ip_address = split("/", cidr)[0]
      end_ip_address   = split("/", cidr)[0]
    } }
  )
}

# PostgreSQL database initialization for Haystack DocumentStore with FTS
# This creates the schema required by Haystack with Full Text Search capabilities
# Includes tsvector column, GIN index, and trigger for automatic tsvector updates
resource "terraform_data" "postgresql_init" {
  depends_on = [module.postgresql]

  # This resource uses a null resource pattern to execute initialization SQL
  # In production, this would be better handled by a container init job or migration tool
  triggers_replace = {
    database_id = module.postgresql.resource_id
  }

  # Note: Actual SQL execution requires psql client or Azure CLI
  # The schema below should be executed after initial terraform apply
  # SQL script is provided as inline documentation:
  #
  # -- Haystack documents table with FTS support
  # CREATE TABLE IF NOT EXISTS documents (
  #   id TEXT PRIMARY KEY,
  #   content TEXT NOT NULL,
  #   content_type TEXT DEFAULT 'text',
  #   meta JSONB DEFAULT '{}',
  #   score FLOAT DEFAULT NULL,
  #   embedding FLOAT[] DEFAULT NULL,
  #   content_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
  # );
  # 
  # -- GIN index for full text search performance
  # CREATE INDEX IF NOT EXISTS documents_content_tsv_idx ON documents USING GIN(content_tsv);
  # 
  # -- Additional index on metadata for filtering
  # CREATE INDEX IF NOT EXISTS documents_meta_idx ON documents USING GIN(meta);
  # 
  # -- Index on id for fast lookups
  # CREATE INDEX IF NOT EXISTS documents_id_idx ON documents(id);

  provisioner "local-exec" {
    command = "echo 'PostgreSQL schema for Haystack DocumentStore with FTS must be initialized manually or via container init script'"
  }
}
