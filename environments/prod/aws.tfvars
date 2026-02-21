# environments/prod/aws.tfvars
# ⚠️  Apply only via CI/CD with approval gate — never manually

project_name = "myapp"
environment  = "prod"

aws_region         = "us-east-1"
vpc_cidr           = "10.2.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24", "10.2.13.0/24"]

db_name     = "appdb"
db_username = "dbadmin"

alert_email = "prod-alerts@yourcompany.com"
