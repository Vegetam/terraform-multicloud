# modules/networking/gcp/main.tf
# GCP VPC with custom subnets and secondary ranges for GKE pods/services

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_name" {
  type = string
}

variable "subnets" {
  type = any
}

resource "google_compute_network" "main" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false  # Custom subnets only
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnets" {
  for_each = { for s in var.subnets : s.name => s }

  name          = "${var.network_name}-${each.value.name}"
  ip_cidr_range = each.value.ip_cidr_range
  region        = lookup(each.value, "region", var.region)
  network       = google_compute_network.main.id
  project       = var.project_id

  private_ip_google_access = true  # Allow GCP API access without public IP

  dynamic "secondary_ip_range" {
    for_each = lookup(each.value, "secondary_ranges", [])
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }
}

# ─── Cloud Router + NAT for private nodes ────────────────────────
resource "google_compute_router" "main" {
  name    = "${var.network_name}-router"
  network = google_compute_network.main.id
  region  = var.region
  project = var.project_id
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ─── Firewall: allow internal traffic ────────────────────────────
resource "google_compute_firewall" "internal" {
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.main.id
  project = var.project_id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [for s in var.subnets : s.ip_cidr_range]
  priority      = 1000
}

output "network_id" {
  value = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "gke_subnet_name" {
  value = google_compute_subnetwork.subnets["gke-subnet"].name
}

output "subnet_ids" {
  value = { for k, s in google_compute_subnetwork.subnets : k => s.id }
}