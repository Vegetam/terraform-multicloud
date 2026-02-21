# environments/staging/aws.tfvars

project_name = "myapp"
environment  = "staging"

aws_region         = "us-east-1"
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

db_name     = "appdb"
db_username = "dbadmin"

alert_email = "staging-alerts@yourcompany.com"
