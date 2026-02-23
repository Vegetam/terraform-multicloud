# ============================================================
# Azure Infrastructure — Enterprise-Ready Baseline
# Provisions: Resource Group, VNet, AKS, PostgreSQL Flexible Server, Blob Storage, Key Vault
#
# Authentication: Uses ARM_* env vars, Azure CLI, or Workload Identity Federation in CI.
# No secrets are stored in tfvars or committed files.
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend config is provided via -backend-config=<file>
  # Example: terraform init -backend-config=../environments/dev/backend-azure.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}

# ─── Naming / environment toggles ─────────────────────────────────
resource "random_string" "unique" {
  length  = 6
  upper   = false
  special = false
}

locals {
  # Private-by-default for non-dev.
  enable_private_endpoints = var.environment != "dev"

  # Normalize to lowercase alnum for resources with strict naming.
  base = lower(replace(var.project_name, "/[^0-9a-z]/", ""))

  # Storage account: 3-24 chars, lowercase letters/numbers only, globally unique.
  storage_account_name = substr("${local.base}${var.environment}${random_string.unique.result}", 0, 24)

  # Key Vault: 3-24 chars, alphanumeric/hyphen allowed; keep it simple and collision-proof.
  key_vault_name = substr("kv${local.base}${var.environment}${random_string.unique.result}", 0, 24)

  # PostgreSQL server: up to 63 chars, must start with a letter. Use a stable prefix.
  postgres_server_name = substr("pg${local.base}${var.environment}${random_string.unique.result}", 0, 63)

  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Resource Group ───────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.azure_location

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ─── Monitoring ───────────────────────────────────────────────────
module "monitoring" {
  source = "../modules/monitoring/azure"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  project_name        = var.project_name
  environment         = var.environment
}

# ─── Networking ───────────────────────────────────────────────────
module "vnet" {
  source = "../modules/networking/azure"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  project_name        = var.project_name
  environment         = var.environment

  vnet_address_space            = ["10.1.0.0/16"]
  aks_subnet_cidr               = "10.1.1.0/24"
  database_subnet_cidr          = "10.1.2.0/24"
  appgw_subnet_cidr             = "10.1.3.0/24"
  private_endpoints_subnet_cidr = local.enable_private_endpoints ? "10.1.4.0/24" : null
}

# ─── Key Vault ────────────────────────────────────────────────────
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  soft_delete_retention_days = 90
  purge_protection_enabled   = var.environment == "prod"

  # Public access off when using Private Endpoints.
  public_network_access_enabled = local.enable_private_endpoints ? false : true

  # Lock down network access in non-dev.
  dynamic "network_acls" {
    for_each = local.enable_private_endpoints ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = "AzureServices"
      virtual_network_subnet_ids = [module.vnet.private_endpoints_subnet_id]
    }
  }

  # Terraform runner / principal must be able to manage secrets deterministically.
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
    ]
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ─── Deterministic DB secret (no manual pre-steps) ────────────────
resource "random_password" "db_admin" {
  length           = 32
  special          = true
  override_special = "!@#$%^*-_=+?"
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "postgres-admin-password"
  value        = random_password.db_admin.result
  key_vault_id = azurerm_key_vault.main.id

  # Avoid accidental rotation on every plan/apply; rotate intentionally.
  lifecycle {
    ignore_changes = [value]
  }
}

# ─── Private DNS zones (Storage/Key Vault) ────────────────────────
resource "azurerm_private_dns_zone" "blob" {
  count               = local.enable_private_endpoints ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = local.enable_private_endpoints ? 1 : 0
  name                  = "${local.name_prefix}-blob-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  resource_group_name   = azurerm_resource_group.main.name
  virtual_network_id    = module.vnet.vnet_id
}

resource "azurerm_private_dns_zone" "keyvault" {
  count               = local.enable_private_endpoints ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  count                 = local.enable_private_endpoints ? 1 : 0
  name                  = "${local.name_prefix}-kv-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  resource_group_name   = azurerm_resource_group.main.name
  virtual_network_id    = module.vnet.vnet_id
}

# ─── Azure Blob Storage ───────────────────────────────────────────
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "GRS" : "LRS"
  account_kind             = "StorageV2"

  enable_https_traffic_only       = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = local.enable_private_endpoints ? false : true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_storage_account_network_rules" "main" {
  count              = local.enable_private_endpoints ? 1 : 0
  storage_account_id = azurerm_storage_account.main.id

  default_action             = "Deny"
  bypass                     = ["AzureServices"]
  virtual_network_subnet_ids = [module.vnet.private_endpoints_subnet_id]
}

resource "azurerm_storage_container" "app_data" {
  name                  = "app-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ─── Private Endpoints (Storage Blob + Key Vault) ─────────────────
resource "azurerm_private_endpoint" "storage_blob" {
  count               = local.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pep-blob"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "${local.name_prefix}-pep-blob-conn"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.blob]
}

resource "azurerm_private_endpoint" "keyvault" {
  count               = local.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pep-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "${local.name_prefix}-pep-kv-conn"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault[0].id]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.keyvault]
}

# ─── AKS Cluster ─────────────────────────────────────────────────
# FIX: kubernetes_version aggiornato da 1.28 (EOL) a 1.30
module "aks" {
  source = "../modules/compute/azure-aks"

  cluster_name        = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kubernetes_version  = "1.30"
  dns_prefix          = local.name_prefix
  vnet_subnet_id      = module.vnet.aks_subnet_id

  default_node_pool = {
    name                = "system"
    vm_size             = var.environment == "prod" ? "Standard_D4s_v3" : "Standard_D2s_v3"
    min_count           = var.environment == "prod" ? 3 : 1
    max_count           = var.environment == "prod" ? 10 : 3
    enable_auto_scaling = true
    os_disk_size_gb     = 100
  }

  identity_type    = "SystemAssigned"
  enable_oms_agent = true
  log_analytics_id = module.monitoring.log_analytics_workspace_id
}

# ─── Key Vault access for AKS kubelet identity ───────────────────
# FIX: era erroneamente annidato dentro il blocco module "aks" — ora correttamente al top level
resource "azurerm_key_vault_access_policy" "aks_kubelet" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.aks.kubelet_identity_object_id

  secret_permissions = ["Get", "List"]
}

# ─── PostgreSQL Flexible Server (private-by-default) ──────────────
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.name_prefix}-postgres-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = azurerm_resource_group.main.name
  virtual_network_id    = module.vnet.vnet_id
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                = local.postgres_server_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  version             = "15"

  delegated_subnet_id = module.vnet.database_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  administrator_login    = var.db_username
  administrator_password = azurerm_key_vault_secret.db_password.value

  # Private-only access in non-dev environments.
  public_network_access_enabled = local.enable_private_endpoints ? false : true

  sku_name   = var.environment == "prod" ? "GP_Standard_D4s_v3" : "B_Standard_B1ms"
  storage_mb = var.environment == "prod" ? 102400 : 32768

  backup_retention_days        = var.environment == "prod" ? 35 : 7
  geo_redundant_backup_enabled = var.environment == "prod"

  high_availability {
    mode = var.environment == "prod" ? "ZoneRedundant" : "Disabled"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}
