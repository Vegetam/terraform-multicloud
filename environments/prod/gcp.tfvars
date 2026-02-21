# environments/prod/gcp.tfvars
# ⚠️  Apply only via CI/CD with approval gate — never manually

project_name = "myapp"
environment  = "prod"

gcp_project_id = "my-gcp-project-prod"
gcp_region     = "us-central1"

db_name     = "appdb"
db_username = "dbadmin"

# Optional: Cloud Monitoring alert destination
alert_email = "prod-alerts@yourcompany.com"

# Production hardening toggles
gke_enable_network_policy   = true
enable_binary_authorization = true

# If set to true, the GKE control plane endpoint becomes private-only.
# This requires private connectivity from your CI runner (e.g., self-hosted runner in VPC).
gke_enable_private_endpoint = true
