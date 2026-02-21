# gcp/outputs.tf

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.main.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name (for Cloud SQL Proxy)"
  value       = google_sql_database_instance.main.connection_name
}

output "gcs_bucket_name" {
  description = "App data GCS bucket name"
  value       = google_storage_bucket.app_data.name
}

output "app_service_account_email" {
  description = "App service account email (for Workload Identity binding)"
  value       = google_service_account.app.email
}

output "vpc_network_name" {
  description = "VPC network name"
  value       = module.vpc.network_name
}

output "gcp_project_id" {
  description = "GCP project id"
  value       = var.gcp_project_id
}

output "gcp_region" {
  description = "GCP region"
  value       = var.gcp_region
}

output "db_password_secret_name" {
  description = "Secret Manager secret id storing the Cloud SQL password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "cloud_operations_dashboard_id" {
  description = "Cloud Monitoring dashboard id"
  value       = module.monitoring.dashboard_id
}
