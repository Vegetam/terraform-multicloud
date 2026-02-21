# environments/prod/azure.tfvars
# ⚠️  Apply only via CI/CD with approval gate — never manually

project_name = "myapp"
environment  = "prod"

azure_location = "East US"
db_username    = "dbadmin"
