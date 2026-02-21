# azure/variables.tf

variable "project_name" {
  description = "Name of the project (used as resource prefix)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "azure_location" {
  description = "Azure region/location (e.g., East US, West Europe)"
  type        = string
}

variable "db_username" {
  description = "Admin username for Azure Database for PostgreSQL"
  type        = string
}
