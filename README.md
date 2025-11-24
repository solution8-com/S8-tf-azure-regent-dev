# Minimal Azure Infrastructure for Haystack + n8n + Cohere Rerank

This Terraform configuration deploys a minimal, development-focused Azure infrastructure supporting:

- **Haystack**: Full-featured document search and LLM orchestration service
- **n8n**: Workflow automation platform
- **PostgreSQL**: Backend database with Full Text Search (FTS) for Haystack
- **Azure AI Foundry**: Cohere Rerank v3.5 deployment for document reranking

## ⚠️ Important Notes

### Cohere Rerank v3.5 Deployment Limitation

As of December 2024, Cohere models in Azure may not be directly deployable via Terraform's `azurerm` provider. The current implementation creates an Azure Cognitive Services account (OpenAI kind) as the foundation, but **the actual Cohere Rerank v3.5 model deployment may require manual configuration through Azure AI Studio**.

URL to Azure AI Studio Model Card: https://ai.azure.com/explore/models/Cohere-rerank-v3.5/version/1/registry/azureml-cohere?tid=9de3d9c3-b0bb-4d2e-93ab-f6407a8b3793

**Alternatives**:
1. Deploy Cohere Rerank v3.5 manually via Azure AI Studio (documented below)

This limitation is documented to maintain transparency. Terraform provider updates may enable fully automated Cohere deployments.

## Architecture Overview

### Components

1. **Resource Group** (North Europe)
   - Single container for all infrastructure resources
   - All data remains within EU region for compliance

2. **Container Apps Environment**
   - Managed runtime environment for containerized applications
   - System-assigned managed identity for secure access to Azure resources

3. **n8n Container App**
   - Vanilla n8n instance for workflow automation
   - SQLite database persisted to Azure Files
   - No custom plugins or modifications
   - Optional Entra ID authentication or IP whitelisting

4. **Haystack Container App**
   - Full document ingestion and query REST API
   - PostgreSQL Full Text Search retriever using:
     - `tsvector` for text indexing
     - `tsquery` for search queries
     - `ts_rank` / `ts_rank_cd` for relevance scoring
     - GIN indexing for performance
   - Cohere Rerank v3.5 for post-retrieval reranking
   - External OpenAI-compatible endpoint for LLM generation

5. **PostgreSQL Flexible Server**
   - Backend for Haystack DocumentStore
   - Configured with Full Text Search (FTS)
   - Supabase-compatible PostgreSQL FTS semantics
   - Schema includes:
     - `documents` table with `id`, `content`, `meta` (JSONB), `content_tsv` (tsvector)
     - GIN index on `content_tsv` for fast FTS queries
     - Metadata indexing for filtering

6. **Storage Account + Azure Files**
   - Persistent storage for n8n SQLite database
   - Mounted at `/home/node/.n8n` in n8n container
   - Ensures workflow state survives container restarts

7. **Azure AI Foundry Hub**
   - Cohere Rerank v3.5 deployment
   - Endpoint and API key exposed to Haystack via environment variables
   - Used by Haystack for reranking retrieved documents

8. **Key Vault**
   - Secure storage for:
     - PostgreSQL admin password
     - External OpenAI API key
   - Accessed by container apps via managed identity

### PostgreSQL Full Text Search Configuration

The PostgreSQL database is configured for Supabase-compatible FTS:

```sql
-- Documents table with FTS support
CREATE TABLE documents (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  content_type TEXT DEFAULT 'text',
  meta JSONB DEFAULT '{}',
  score FLOAT DEFAULT NULL,
  embedding FLOAT[] DEFAULT NULL,
  content_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);

-- GIN index for full text search performance
CREATE INDEX documents_content_tsv_idx ON documents USING GIN(content_tsv);

-- Metadata index for filtering
CREATE INDEX documents_meta_idx ON documents USING GIN(meta);

-- Query example using ts_rank for relevance scoring
SELECT id, content, ts_rank(content_tsv, plainto_tsquery('english', 'search term')) AS rank
FROM documents
WHERE content_tsv @@ plainto_tsquery('english', 'search term')
ORDER BY rank DESC
LIMIT 10;
```

This schema must be manually created after initial `terraform apply` or via a container init script.

## Deployment

### Prerequisites

1. Azure subscription with appropriate permissions
2. Terraform >= 1.8, < 2.0
3. Azure CLI (optional, for authentication)
4. Remote state storage (Azure Blob Storage container)

### Required Variables

Create a `terraform.tfvars` file (never commit to Git):

```hcl
subscription_id = "your-azure-subscription-id"

# PostgreSQL admin password
postgres_admin_password = "SecurePassword123!"

# External OpenAI-compatible endpoint (in separate tenant)
external_openai_endpoint = "https://your-openai.openai.azure.com/"
external_openai_api_key = "your-openai-api-key"
external_openai_deployment_name = "gpt-4"

# Authentication: Either IP whitelisting or Entra ID
allowed_ip_ranges = ["1.2.3.4/32"]  # Your IP address
# OR
enable_entra_auth = true

# Optional: Custom tags
tags = {
  Environment = "Development"
  Project     = "Haystack-n8n"
}
```

### Backend Configuration

Create a `backend.hcl` file for remote state:

```hcl
resource_group_name  = "tfstate-rg"
storage_account_name = "yourtfstatestorage"
container_name       = "tfstate"
key                  = "dev.terraform.tfstate"
```

### Deployment Steps

1. **Initialize Terraform with remote backend**:
   ```bash
   terraform init -backend-config=backend.hcl
   ```

2. **Review the execution plan**:
   ```bash
   terraform plan -var-file=terraform.tfvars
   ```

3. **Apply the configuration**:
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```

4. **Initialize PostgreSQL schema** (manual step):
   ```bash
   # Connect to PostgreSQL and execute the schema SQL shown above
   az postgres flexible-server execute \
     --name $(terraform output -raw postgresql_fqdn | cut -d. -f1) \
     --admin-user psqladmin \
     --admin-password "$POSTGRES_PASSWORD" \
     --database-name haystack \
     --querytext "@schema.sql"
   ```

5. **Deploy Cohere Rerank v3.5**:
   
   If Terraform doesn't automatically deploy the Cohere model, you can deploy it manually:
   
   a. Navigate to [Azure AI Studio](https://ai.azure.com/)
   
   b. Select the Cognitive Services resource created by Terraform
   
   c. Navigate to "Model deployments" or "Models"
   
   d. Search for "Cohere Rerank v3.5" or follow the [link to the model card](https://ai.azure.com/explore/models/Cohere-rerank-v3.5/version/1/registry/azureml-cohere?tid=9de3d9c3-b0bb-4d2e-93ab-f6407a8b3793) 
   
   e. Deploy the model with the following settings:
      - Deployment name: `cohere-rerank-v3.5`
      - Model version: Latest available
      - Region: North Europe (or closest EU region)
   
   f. Copy the endpoint URL and credentials
   
   g. Update Key Vault secret


6. **Access the services**:
   - n8n: `terraform output -raw n8n_fqdn_url`
   - Haystack: `terraform output -raw haystack_fqdn_url`

## Authentication and Access Control

### Option 1: IP Whitelisting

Set `allowed_ip_ranges` variable to restrict access to specific IP addresses:

```hcl
allowed_ip_ranges = ["203.0.113.0/24", "198.51.100.42/32"]
```

This restricts both n8n and Haystack endpoints to the specified IP ranges.

### Option 2: Azure Entra ID (Microsoft 365)

Set `enable_entra_auth = true` to require Entra ID login.

**Note**: Full Entra ID integration requires additional Azure AD app registration and configuration not included in this minimal deployment. This is documented as a limitation.

### Default Security

- All endpoints use HTTPS
- PostgreSQL requires SSL connections
- All secrets stored in Key Vault
- Container apps access secrets via managed identity
- No VNet integration (simplified networking for development)

## Regional and Compliance Constraints

- **Primary Region**: North Europe
- **Data Residency**: All data persists within EU regions
- **Cohere Rerank**: Deployed in North Europe if available, otherwise closest EU region
- **OpenAI Endpoint**: External endpoint in separate tenant (region not controlled by this deployment)

## Prohibited Components

The following are explicitly excluded per architecture requirements:

- Vector search engines (Milvus, Qdrant, pgvector, Weaviate, Chroma)
- Dedicated BM25 implementations or pg_bm25 extensions
- External ingestion microservices
- Complex networking (VNets, Private Endpoints, API Management)
- Static Web Apps
- Multi-module or assistant services beyond the minimal set

## Cohere Rerank v3.5 Integration

Haystack uses Cohere Rerank v3.5 deployed in Azure AI Foundry:

1. **Deployment**: Cohere model deployed via Azure Cognitive Services
2. **Endpoint**: Exposed via `azurerm_cognitive_account.ai_hub.endpoint`
3. **Authentication**: API key stored in Key Vault, accessed by Haystack
4. **Usage**: Haystack reranker component calls endpoint with retrieved documents
5. **Output**: Reranked documents with semantic relevance scores

## External OpenAI-Compatible Endpoint

Haystack routes LLM generation calls to an OpenAI-compatible endpoint in a different, client-owned tenant:

- **Endpoint**: Specified via `external_openai_endpoint` variable
- **Authentication**: API key via `external_openai_api_key` variable
- **Model**: Deployment name via `external_openai_deployment_name` variable
- **Tenant**: Endpoint is in a separate Azure tenant (not managed by this Terraform)

This separation allows different teams/tenants to manage LLM infrastructure independently.

## Validation

After deployment, verify:

```bash
# Check all resources are created
terraform state list

# Verify outputs
terraform output

# Test n8n endpoint
curl -I $(terraform output -raw n8n_fqdn_url)

# Test Haystack endpoint
curl -I $(terraform output -raw haystack_fqdn_url)

# Verify PostgreSQL connectivity
psql -h $(terraform output -raw postgresql_fqdn) -U psqladmin -d haystack
```

Expected resource count:
- 1 Resource Group
- 1 Container Apps Environment
- 2 Container Apps (n8n, Haystack)
- 1 PostgreSQL Flexible Server
- 1 Storage Account + 1 File Share
- 1 Key Vault
- 1 AI Foundry Hub (Cognitive Account)
- 1 Cohere Rerank deployment

## Maintenance

### Updating Haystack or n8n

Container images use `:latest` tag by default. To update:

```bash
# Trigger revision update
terraform apply -replace=module.container_app_haystack
terraform apply -replace=module.container_app_n8n
```

### Scaling

Container apps use minimal resources (0.25-0.5 CPU, 0.5-1.0 GB RAM). To scale:

1. Edit `main.aca.tf`
2. Update `cpu` and `memory` values
3. Run `terraform apply`

### Backup

- **n8n**: SQLite database backed up via Azure Files snapshot
- **PostgreSQL**: Enable Azure Backup or configure automated backups
- **Terraform State**: Stored in Azure Blob Storage (enable versioning)

## Limitations

1. **Manual Schema Initialization**: PostgreSQL schema must be created manually after first apply
2. **No VNet Integration**: Simplified networking means public endpoints with authentication
3. **Development-Focused**: Minimal SKUs and single-instance deployments
4. **Cohere Model Availability**: May require manual deployment via Azure AI Studio if Terraform provider doesn't support
5. **Entra ID Authentication**: Requires manual Azure AD app registration for full implementation

## Troubleshooting

### Container App Won't Start

Check logs:
```bash
az containerapp logs show \
  --name $(terraform output -json | jq -r '.haystack_fqdn_url.value' | cut -d. -f1) \
  --resource-group $(terraform output -raw resource_group_name) \
  --follow
```

### PostgreSQL Connection Failed

Verify firewall rules:
```bash
az postgres flexible-server firewall-rule list \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw postgresql_fqdn | cut -d. -f1)
```

### Key Vault Access Denied

Ensure managed identity has proper role assignment:
```bash
az keyvault set-policy \
  --name $(terraform output -raw key_vault_uri | cut -d/ -f3 | cut -d. -f1) \
  --object-id $(az identity show --ids $(terraform state show azurerm_user_assigned_identity.this | grep id | head -1 | cut -d= -f2 | tr -d '"' | xargs) --query principalId -o tsv) \
  --secret-permissions get list
```

## Cost Estimation

Estimated monthly cost (North Europe, development SKUs):

- Container Apps Environment: ~$0 (consumption-based)
- n8n Container App: ~$30 (0.25 vCPU, 0.5 GB RAM)
- Haystack Container App: ~$60 (0.5 vCPU, 1.0 GB RAM)
- PostgreSQL B_Standard_B1ms: ~$25
- Storage Account (LRS): ~$2
- Key Vault: ~$1
- AI Foundry + Cohere: Variable (depends on usage)

**Total**: ~$120-150/month

## Support and Contributions

This is a minimal reference implementation. For production deployments, consider:

- High availability (zone redundancy, replicas)
- VNet integration and private endpoints
- Azure Front Door or Application Gateway
- Monitoring (Application Insights, Log Analytics)
- Automated backups and disaster recovery
- Performance SKUs for production workloads
