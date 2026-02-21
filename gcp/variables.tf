# gcp/variables.tf

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

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region (e.g., us-central1)"
  type        = string
}

variable "db_name" {
  description = "Database name (used by Cloud SQL)"
  type        = string
}

variable "db_username" {
  description = "Database username (used by Cloud SQL)"
  type        = string
}

variable "alert_email" {
  description = "Optional email address for Cloud Monitoring alerts"
  type        = string
  default     = ""
}

variable "gke_enable_network_policy" {
  description = "Enable GKE NetworkPolicy enforcement (Calico)"
  type        = bool
  default     = true
}

variable "gke_master_authorized_networks" {
  description = "Optional list of CIDR blocks allowed to reach the GKE control plane (public endpoint)"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization on the cluster (recommended for production)"
  type        = bool
  default     = false
}

variable "gke_enable_private_endpoint" {
  description = "Enable private control plane endpoint (requires private connectivity to the master endpoint)"
  type        = bool
  default     = false
}

variable "gke_enable_managed_prometheus" {
  description = "Enable Google-managed Prometheus for GKE"
  type        = bool
  default     = true
}
