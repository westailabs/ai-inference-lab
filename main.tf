# ============================================================
# Phase 1: Enable required GCP APIs
# 
# INTERVIEW TOPIC: "How do you handle GCP API enablement?"
# 
# Key points:
# - APIs must be enabled before resources can be created
# - Terraform can manage this declaratively
# - In production, API enablement is usually done once in a 
#   bootstrap/seed project, not in every workspace
# ============================================================

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",           # Cloud Run
    "compute.googleapis.com",       # VPC, firewall, load balancer
    "secretmanager.googleapis.com", # Secret Manager
    "iam.googleapis.com",           # IAM
    "monitoring.googleapis.com",    # Cloud Monitoring
    "artifactregistry.googleapis.com", # Container images
  ])

  project = var.project_id
  service = each.value

  # INTERVIEW: "disable_on_destroy = false prevents accidentally
  # disabling APIs that other resources depend on"
  disable_on_destroy = false
}

# ============================================================
# Output the enabled APIs for verification
# ============================================================

output "enabled_apis" {
  description = "List of enabled GCP APIs"
  value       = [for api in google_project_service.apis : api.service]
}
