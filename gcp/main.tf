# ============================================================
# GCP Infrastructure — Enterprise-ready baseline
# Provisions: VPC, GKE, Cloud SQL (private IP), Cloud Storage, IAM
#
# Authentication: Application Default Credentials (ADC)
# CI/CD: Workload Identity Federation (keyless auth)
# No service account keys are stored in this repository.
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state in Google Cloud Storage
  # Backend config is provided via -backend-config=<file>
  # Example: terraform init -backend-config=../environments/dev/backend-gcp.hcl
  backend "gcs" {}
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  # Authentication via ADC:
  # Local: gcloud auth application-default login
  # CI/CD: Workload Identity Federation (no JSON key needed)
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# ─── Enable APIs ──────────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",          # VPC, firewall, NAT
    "container.googleapis.com",        # GKE
    "iam.googleapis.com",              # IAM
    "sqladmin.googleapis.com",         # Cloud SQL
    "storage.googleapis.com",          # Cloud Storage
    "secretmanager.googleapis.com",    # Secret Manager
    "monitoring.googleapis.com",       # Cloud Monitoring
    "logging.googleapis.com",          # Cloud Logging
    "servicenetworking.googleapis.com" # Private Service Access (Cloud SQL private IP)
  ])

  service            = each.key
  disable_on_destroy = false
}

# ─── Random suffix for globally-unique names ──────────────────────
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Bucket names are global across all GCP projects.
  bucket_name = "${lower(var.project_name)}-${var.environment}-app-data-${random_id.suffix.hex}"

  # Service account id rules: 6-30 chars, lowercase letters/digits/hyphen, start with letter.
  # Keep it short and collision-resistant.
  sa_account_id = substr("${lower(var.project_name)}-${var.environment}-app-${random_id.suffix.hex}", 0, 30)

  db_password_secret_name = "${lower(var.project_name)}-${var.environment}-db-password"
}

# ─── VPC Network ──────────────────────────────────────────────────
module "vpc" {
  source = "../modules/networking/gcp"

  project_id   = var.gcp_project_id
  network_name = "${var.project_name}-${var.environment}-vpc"
  region       = var.gcp_region

  subnets = [
    {
      name          = "gke-subnet"
      ip_cidr_range = "10.2.0.0/24"
      region        = var.gcp_region
      secondary_ranges = [
        { range_name = "pods", ip_cidr_range = "10.2.100.0/22" },
        { range_name = "services", ip_cidr_range = "10.2.104.0/24" },
      ]
    },
    {
      name          = "database-subnet"
      ip_cidr_range = "10.2.1.0/24"
      region        = var.gcp_region
    }
  ]

  depends_on = [google_project_service.apis]
}

# ─── Private Service Access for Cloud SQL private IP ──────────────
resource "google_compute_global_address" "private_service_access" {
  name          = "${var.project_name}-${var.environment}-psa"
  project       = var.gcp_project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = module.vpc.network_self_link

  depends_on = [google_project_service.apis]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = module.vpc.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]

  depends_on = [google_compute_global_address.private_service_access]
}

# ─── Secret Manager (DB password) ─────────────────────────────────
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!@#$%^*-_=+?"
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.gcp_project_id
  secret_id = local.db_password_secret_name

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# ─── GKE Cluster ─────────────────────────────────────────────────
resource "google_container_cluster" "main" {
  name     = "${var.project_name}-${var.environment}-gke"
  location = var.gcp_region # Regional cluster for HA
  project  = var.gcp_project_id

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = module.vpc.network_name
  subnetwork = module.vpc.gke_subnet_name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    # FIX: STABLE channel in prod ensures Kubernetes >= 1.30 (1.28 is EOL).
    # REGULAR in staging/dev receives patches faster.
    channel = var.environment == "prod" ? "STABLE" : "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.gke_enable_private_endpoint
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Prefer PSA/labels over client cert auth.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Optional: restrict access to the public control plane endpoint.
  dynamic "master_authorized_networks_config" {
    for_each = length(var.gke_master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.gke_master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  network_policy {
    enabled  = var.gke_enable_network_policy
    provider = "CALICO"
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  enable_intranode_visibility = var.environment == "prod"

  enable_shielded_nodes = true

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]

    dynamic "managed_prometheus" {
      for_each = var.gke_enable_managed_prometheus ? [1] : []
      content {
        enabled = true
      }
    }
  }

  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gcp_filestore_csi_driver_config { enabled = true }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "main" {
  name     = "main-pool"
  cluster  = google_container_cluster.main.name
  location = var.gcp_region
  project  = var.gcp_project_id

  autoscaling {
    min_node_count = var.environment == "prod" ? 3 : 1
    max_node_count = var.environment == "prod" ? 10 : 3
  }

  node_config {
    machine_type = var.environment == "prod" ? "e2-standard-4" : "e2-medium"
    disk_size_gb = 100
    disk_type    = "pd-ssd"

    # Required for Workload Identity.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Reduce metadata exposure.
    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      project     = var.project_name
      environment = var.environment
    }
  }
}

# ─── Cloud SQL (PostgreSQL) — private IP ─────────────────────────
resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-${var.environment}-postgres"
  database_version = "POSTGRES_15"
  region           = var.gcp_region
  project          = var.gcp_project_id

  deletion_protection = var.environment == "prod"

  settings {
    tier = var.environment == "prod" ? "db-custom-4-15360" : "db-f1-micro"

    availability_type = var.environment == "prod" ? "REGIONAL" : "ZONAL"

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = var.environment == "prod"
      transaction_log_retention_days = var.environment == "prod" ? 7 : 3
      backup_retention_settings {
        retained_backups = var.environment == "prod" ? 30 : 7
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = module.vpc.network_self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      # FIX: record_client_address is disabled by default — it may expose client IP addresses.
      # Enable only if strictly needed for debugging and after a privacy/compliance review.
      record_client_address   = false
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000" # Log slow queries > 1s
    }
    database_flags {
      name  = "max_connections"
      value = "200"
    }
  }

  # Cloud SQL private IP requires Private Service Access.
  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.private_vpc_connection
  ]
}

resource "google_sql_database" "app" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "app" {
  name     = var.db_username
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}

# ─── Cloud Storage ────────────────────────────────────────────────
resource "google_storage_bucket" "app_data" {
  name          = local.bucket_name
  location      = var.gcp_region
  project       = var.gcp_project_id
  force_destroy = var.environment != "prod"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

# ─── Service Account for Workload Identity ────────────────────────
resource "google_service_account" "app" {
  account_id   = local.sa_account_id
  display_name = "App Service Account (${var.environment})"
  project      = var.gcp_project_id
}

# FIX: sostituito roles/storage.objectAdmin (troppo permissivo) con ruoli granulari.
# The service account can create/update/delete objects (Creator) and read them (Viewer).
resource "google_storage_bucket_iam_member" "app_storage_write" {
  bucket = google_storage_bucket.app_data.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.app.email}"
}

resource "google_storage_bucket_iam_member" "app_storage_read" {
  bucket = google_storage_bucket.app_data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.app.email}"
}

# To allow deleting objects (needed for lifecycle/cleanup),
# add this additional binding (optional, commented out by default):
# resource "google_storage_bucket_iam_member" "app_storage_delete" {
#   bucket = google_storage_bucket.app_data.name
#   role   = "roles/storage.legacyBucketWriter"
#   member = "serviceAccount:${google_service_account.app.email}"
# }

# Allow the app service account to read the DB password from Secret Manager.
resource "google_secret_manager_secret_iam_member" "app_secret_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# Bind GKE Workload Identity (KSA -> GSA)
resource "google_service_account_iam_binding" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[app/app-service-account]"
  ]
}

# ─── Monitoring (Cloud Operations) ───────────────────────────────
module "monitoring" {
  source = "../modules/monitoring/gcp"

  project_id             = var.gcp_project_id
  project_name           = var.project_name
  environment            = var.environment
  region                 = var.gcp_region
  cloud_sql_instance_name = google_sql_database_instance.main.name
  gke_cluster_name        = google_container_cluster.main.name
  alert_email            = var.alert_email

  depends_on = [google_project_service.apis]
}
