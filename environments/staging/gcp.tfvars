# environments/staging/gcp.tfvars

project_name = "myapp"
environment  = "staging"

gcp_project_id = "my-gcp-project-staging"
gcp_region     = "us-central1"

db_name     = "appdb"
db_username = "dbadmin"

# Optional: Cloud Monitoring alert destination
alert_email = "staging-alerts@yourcompany.com"

# Optional: tighten cluster security
gke_enable_network_policy   = true
enable_binary_authorization = false
gke_enable_private_endpoint = false
