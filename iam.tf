# ============================================================
# Phase 3 & 4: IAM — Service Accounts & Least Privilege
#
# INTERVIEW TOPIC: "How do you handle IAM in Terraform?"
#
# Key points:
# - Dedicated service account per service (not default compute SA)
# - Least privilege — only the permissions the service needs
# - Default compute SA has Editor role = way too broad
# - Service accounts are identities, not people
# ============================================================

# Dedicated service account for Cloud Run
resource "google_service_account" "cloud_run" {
  account_id   = "ai-inference-runner"
  display_name = "AI Inference Cloud Run Service"
  description  = "Service account for the AI inference Cloud Run service"
  project      = var.project_id
}

# INTERVIEW: "I never use the default compute service account.
# It has Editor role which violates least privilege. Each service
# gets its own SA with only the permissions it needs."

# Allow Cloud Run SA to read secrets
resource "google_project_iam_member" "cloud_run_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Allow Cloud Run SA to write logs
resource "google_project_iam_member" "cloud_run_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Allow Cloud Run SA to write metrics
resource "google_project_iam_member" "cloud_run_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ============================================================
# Outputs
# ============================================================

output "cloud_run_service_account" {
  description = "Cloud Run service account email"
  value       = google_service_account.cloud_run.email
}
