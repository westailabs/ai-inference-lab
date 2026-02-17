# ============================================================
# Phase 2: Networking — VPC, Subnets, Firewall
#
# INTERVIEW TOPIC: "Walk me through your network design"
#
# Key points:
# - Custom VPC over default — explicit control, no surprises
# - Private Google Access lets Cloud Run reach GCP services
#   without public IPs
# - Firewall rules: deny-all default, whitelist what's needed
# - Serverless VPC Connector bridges Cloud Run ↔ VPC
# ============================================================

# Custom VPC — never use the default VPC in production
resource "google_compute_network" "main" {
  name                    = "ai-inference-vpc"
  auto_create_subnetworks = false # INTERVIEW: "I always use custom subnets for control"
  project                 = var.project_id

  depends_on = [google_project_service.apis["compute.googleapis.com"]]
}

# Subnet with Private Google Access
resource "google_compute_subnetwork" "main" {
  name          = "ai-inference-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.main.id

  # INTERVIEW: "Private Google Access lets resources reach
  # GCP APIs without needing external IPs — reduces attack surface"
  private_ip_google_access = true
}

# ============================================================
# Firewall Rules
#
# INTERVIEW TOPIC: "How do you handle firewall rules?"
# Answer: "Default deny-all ingress. Explicit allow rules 
# scoped by tag or service account. No 0.0.0.0/0 allow-all."
# ============================================================

# Allow health checks from GCP load balancer ranges
resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  # GCP health check IP ranges (required for load balancers)
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["ai-inference"]

  description = "Allow GCP health check probes"
}

# Allow internal traffic within the VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
  description   = "Allow all internal VPC traffic"
}

# ============================================================
# Serverless VPC Access Connector
# Bridges Cloud Run (serverless) into the VPC
#
# INTERVIEW: "Cloud Run is serverless and runs outside your VPC
# by default. The VPC connector gives it a path into your 
# private network for accessing internal resources."
# ============================================================

# VPC Access Connector — disabled due to health check failures
# Re-enable when needed for Cloud Run → private VPC access
# The connector spins up f1-micro instances; may need billing/quota adjustments

# resource "google_project_service" "vpcaccess" {
#   project            = var.project_id
#   service            = "vpcaccess.googleapis.com"
#   disable_on_destroy = false
# }

# resource "google_vpc_access_connector" "main" {
#   name          = "ai-vpc-connector"
#   region        = var.region
#   network       = google_compute_network.main.name
#   ip_cidr_range = "10.8.0.0/28"
#   machine_type  = "f1-micro"
#   min_instances = 2
#   max_instances = 3
#   depends_on    = [google_project_service.vpcaccess]
# }

# ============================================================
# Outputs
# ============================================================

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "subnet_cidr" {
  description = "Subnet CIDR range"
  value       = google_compute_subnetwork.main.ip_cidr_range
}

# output "vpc_connector_name" {
#   description = "Serverless VPC connector for Cloud Run"
#   value       = google_vpc_access_connector.main.name
# }
