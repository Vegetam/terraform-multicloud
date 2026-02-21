# environments/dev/gcp.tfvars
# Development environment (GCP)

project_name = "myapp"
environment  = "dev"

gcp_project_id = "my-gcp-project-dev"
gcp_region     = "us-central1"

db_name     = "appdb"
db_username = "dbadmin"

# Optional: Cloud Monitoring alert destination
alert_email = "dev-alerts@yourcompany.com"

# Optional: tighten cluster security (safe defaults)
gke_enable_network_policy   = true
enable_binary_authorization = false
gke_enable_private_endpoint = false
