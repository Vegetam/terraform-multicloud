# environments/dev/aws.tfvars
# Development environment (AWS)

project_name = "myapp"
environment  = "dev"

aws_region         = "us-east-1"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

db_name     = "appdb"
db_username = "dbadmin"

alert_email = "dev-alerts@yourcompany.com"

# FIX: CIDR espliciti per l'endpoint pubblico EKS in dev.
# Sostituire con il proprio IP/CIDR aziendale o VPN (es. "203.0.113.10/32").
eks_public_access_cidrs = ["10.0.0.0/8"]
