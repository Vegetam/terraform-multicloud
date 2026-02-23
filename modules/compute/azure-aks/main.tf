# modules/compute/azure-aks/main.tf
# AKS cluster with SystemAssigned identity, autoscaling, OMS monitoring

variable "cluster_name" { type = string }
variable "dns_prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_subnet_id" { type = string }
variable "kubernetes_version" { type = string }
variable "default_node_pool" { type = any }
variable "identity_type" {
  type    = string
  default = "SystemAssigned"
}
variable "enable_oms_agent" {
  type    = bool
  default = true
}
variable "log_analytics_id" {
  type    = string
  default = null
}
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version

  # Managed identity — no Service Principal credentials to rotate
  identity {
    type = var.identity_type
  }

  default_node_pool {
    name                = lookup(var.default_node_pool, "name", "system")
    vm_size             = lookup(var.default_node_pool, "vm_size", "Standard_D2s_v3")
    vnet_subnet_id      = var.vnet_subnet_id
    enable_auto_scaling = lookup(var.default_node_pool, "enable_auto_scaling", true)
    min_count           = lookup(var.default_node_pool, "min_count", 1)
    max_count           = lookup(var.default_node_pool, "max_count", 3)
    os_disk_size_gb     = lookup(var.default_node_pool, "os_disk_size_gb", 100)
    os_disk_type        = "Managed"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
  }

  # Azure Monitor integration
  dynamic "oms_agent" {
    for_each = var.enable_oms_agent ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_id
    }
  }

  # Auto-upgrade patch versions
  automatic_channel_upgrade = "patch"

  tags = {
    ManagedBy = "Terraform"
  }
}

output "cluster_id" { value = azurerm_kubernetes_cluster.main.id }
output "cluster_name" { value = azurerm_kubernetes_cluster.main.name }
output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}
output "kubelet_identity_object_id" { value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id }
output "cluster_identity_principal_id" { value = azurerm_kubernetes_cluster.main.identity[0].principal_id }
