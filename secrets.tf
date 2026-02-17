# ============================================================
# Phase 4: Secret Manager
#
# INTERVIEW TOPIC: "How do you manage secrets in Terraform?"
#
# Key points:
# - Never hardcode secrets in .tf files or tfvars
# - Secret Manager stores the secret, Terraform creates the container
# - Actual secret VALUES are set manually or via CI/CD, not in code
# - Cloud Run accesses secrets at runtime via env vars or mounted volumes
# - Mark variables as sensitive = true to prevent plan output leaks
# ============================================================

# Create a secret container (not the value — that's set separately)
resource "google_secret_manager_secret" "api_key" {
  secret_id = "ai-inference-api-key"
  project   = var.project_id

  replication {
    auto {}
  }

  # INTERVIEW: "I create the secret resource in Terraform but set
  # the actual value through gcloud CLI or CI/CD pipeline. Secret
  # values should never appear in Terraform state or plan output."

  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
}

# Create an initial version with a placeholder
# In production, this would be set via CI/CD or gcloud
resource "google_secret_manager_secret_version" "api_key_v1" {
  secret      = google_secret_manager_secret.api_key.id
  secret_data = var.api_key_value

  lifecycle {
    # INTERVIEW: "ignore_changes on secret_data means Terraform
    # won't try to overwrite manually rotated secrets"
    ignore_changes = [secret_data]
  }
}

# ============================================================
# Outputs
# ============================================================

output "secret_name" {
  description = "Secret Manager secret resource name"
  value       = google_secret_manager_secret.api_key.secret_id
}
