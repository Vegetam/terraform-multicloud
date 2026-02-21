# modules/networking/azure/main.tf
# Azure VNet with AKS, database, Application Gateway, and (optional) Private Endpoints subnets.

variable "project_name"        { type = string }
variable "environment"         { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "vnet_address_space"  { type = list(string) }
variable "aks_subnet_cidr"     { type = string }
variable "database_subnet_cidr" { type = string }
variable "appgw_subnet_cidr"   { type = string }

# When set, an additional subnet is created for Private Endpoints.
# Keep this subnet dedicated to Private Endpoints only.
variable "private_endpoints_subnet_cidr" {
  type    = string
  default = null
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_subnet" "aks" {
  name                 = "${local.name_prefix}-aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_cidr]

  # Common endpoints used by workloads (optional).
  service_endpoints = ["Microsoft.Sql", "Microsoft.Storage"]
}

resource "azurerm_subnet" "database" {
  name                 = "${local.name_prefix}-db-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.database_subnet_cidr]

  # Required for PostgreSQL Flexible Server delegation.
  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "appgw" {
  name                 = "${local.name_prefix}-appgw-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.appgw_subnet_cidr]
}

resource "azurerm_subnet" "private_endpoints" {
  count                = var.private_endpoints_subnet_cidr != null ? 1 : 0
  name                 = "${local.name_prefix}-pep-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoints_subnet_cidr]

  # Required for Private Endpoints to function.
  private_endpoint_network_policies_enabled = false
}

# ─── Network Security Groups ──────────────────────────────────────
resource "azurerm_network_security_group" "aks" {
  name                = "${local.name_prefix}-aks-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "allow-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# ─── Outputs ──────────────────────────────────────────────────────
output "vnet_id"            { value = azurerm_virtual_network.main.id }
output "aks_subnet_id"      { value = azurerm_subnet.aks.id }
output "database_subnet_id" { value = azurerm_subnet.database.id }
output "appgw_subnet_id"    { value = azurerm_subnet.appgw.id }
output "private_endpoints_subnet_id" { value = try(azurerm_subnet.private_endpoints[0].id, null) }
