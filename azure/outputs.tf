# azure/outputs.tf

output "resource_group_name" {
  description = "Azure resource group name"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = module.aks.cluster_name
}

output "aks_kube_config" {
  description = "AKS kubeconfig"
  value       = module.aks.kube_config
  sensitive   = true
}

output "postgres_server_name" {
  description = "Azure PostgreSQL Flexible Server name"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "storage_account_name" {
  description = "Azure Blob Storage account name"
  value       = azurerm_storage_account.main.name
}

output "key_vault_uri" {
  description = "Azure Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = module.monitoring.log_analytics_workspace_id
}
