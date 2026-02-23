# modules/monitoring/gcp/main.tf
# Cloud Operations baseline: alert policies + dashboard.
#
# Notes:
# - Metric filters are intentionally broad to keep the baseline portable.
# - Tighten filters (e.g., by resource labels) once you standardize naming/labels.

variable "project_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "cloud_sql_instance_name" {
  type = string
}

variable "gke_cluster_name" {
  type = string
}

variable "alert_email" {
  type    = string
  default = ""
}

locals {
  # Avoid index errors when alert_email is empty (count = 0).
  notification_channels = try([google_monitoring_notification_channel.email[0].name], [])
  dashboard_display     = "${var.project_name}-${var.environment}-ops"
}

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "${var.project_name}-${var.environment}-alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# Cloud SQL CPU utilization alert (baseline)
resource "google_monitoring_alert_policy" "cloudsql_cpu" {
  project      = var.project_id
  display_name = "${var.project_name}-${var.environment} Cloud SQL CPU high"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Cloud SQL CPU utilization is above threshold."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Cloud SQL CPU utilization"

    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
}

# GKE node CPU utilization alert (baseline via GCE instance metric)
resource "google_monitoring_alert_policy" "gke_node_cpu" {
  project      = var.project_id
  display_name = "${var.project_name}-${var.environment} GKE node CPU high"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Node CPU utilization is above threshold."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Node CPU utilization"

    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.85
      duration        = "600s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
}

# Simple Cloud Operations dashboard (baseline)
resource "google_monitoring_dashboard" "main" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = local.dashboard_display
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Cloud SQL CPU utilization"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
            yAxis = { label = "utilization", scale = "LINEAR" }
          }
        },
        {
          title = "GCE instance CPU utilization (GKE nodes)"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
            yAxis = { label = "utilization", scale = "LINEAR" }
          }
        }
      ]
    }
  })
}

output "dashboard_id" {
  value = google_monitoring_dashboard.main.id
}
