# modules/monitoring/azure/main.tf
# Log Analytics Workspace + Azure Monitor action group for alerts

variable "project_name"        { type = string }
variable "environment"         { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }

variable "alert_email" {
  type    = string
  default = ""
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ─── Action Group for Alerts ─────────────────────────────────────
resource "azurerm_monitor_action_group" "alerts" {
  name                = "${local.name_prefix}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = substr(replace("${var.project_name}${var.environment}", "-", ""), 0, 12)

  dynamic "email_receiver" {
    for_each = var.alert_email != "" ? [1] : []
    content {
      name                    = "ops-team"
      email_address           = var.alert_email
      use_common_alert_schema = true
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

output "log_analytics_workspace_id"   { value = azurerm_log_analytics_workspace.main.id }
output "log_analytics_workspace_name" { value = azurerm_log_analytics_workspace.main.name }
output "action_group_id"              { value = azurerm_monitor_action_group.alerts.id }
