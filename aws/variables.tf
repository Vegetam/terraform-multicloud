variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for multi-AZ deployment"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "dbadmin"
}

variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
}

# FIX: replaces the hardcoded 0.0.0.0/0 CIDR for the EKS public endpoint in dev.
# Imposta il tuo CIDR aziendale/VPN (es. ["203.0.113.0/24"]).
variable "eks_public_access_cidrs" {
  description = "CIDR allowlist for the EKS public API endpoint (used only in dev). Set to your corporate/VPN CIDR — do NOT use 0.0.0.0/0 in real environments."
  type        = list(string)
  default     = ["10.0.0.0/8"] # Safe default: internal ranges only. Override with your actual CIDR.

  validation {
    condition     = alltrue([for c in var.eks_public_access_cidrs : c != "0.0.0.0/0"])
    error_message = "Do not use 0.0.0.0/0 for EKS public access. Use a corporate/VPN CIDR allowlist instead."
  }
}

