# ============================================================
# Phase 3: Cloud Run — Deploy the AI Inference Container
#
# INTERVIEW TOPIC: "Walk me through deploying a container on GCP"
#
# Key points:
# - Cloud Run = fully managed, scales to zero, pay per request
# - vs GKE: Cloud Run for stateless APIs, GKE for complex workloads
# - Secrets injected as env vars at runtime (not baked into image)
# - VPC connector for private network access
# - Concurrency + CPU/memory tuning for AI workloads
# ============================================================

resource "google_cloud_run_v2_service" "inference" {
  name     = var.service_name
  location = var.region
  project  = var.project_id

  # INTERVIEW: "In production, I'd use deletion_protection to prevent
  # accidental terraform destroy. Available in newer provider versions."

  template {
    # Use our dedicated service account, not the default
    service_account = google_service_account.cloud_run.email

    # VPC connector for private network access (disabled — connector health issue)
    # INTERVIEW: "In production, I'd attach a VPC connector so Cloud Run
    # can reach private resources. For public-facing APIs, it's optional."
    # vpc_access {
    #   connector = google_vpc_access_connector.main.id
    #   egress    = "PRIVATE_RANGES_ONLY"
    # }

    # INTERVIEW: "For AI inference, I tune concurrency and resources
    # based on model size. A small classifier might handle 80 concurrent
    # requests, while a large LLM might only handle 1-4."
    scaling {
      min_instance_count = 0 # Scale to zero when idle (cost savings)
      max_instance_count = 3 # Cap for cost control in dev
    }

    containers {
      image = var.container_image

      # Resource limits — tune for your model
      resources {
        limits = {
          cpu    = "1"      # 1 vCPU
          memory = "512Mi"  # 512MB — increase for larger models
        }
        cpu_idle = true # INTERVIEW: "cpu_idle=true releases CPU when not processing,
                        # reduces cost. Disable for latency-sensitive AI inference."
      }

      # Port the container listens on
      ports {
        container_port = 8080
      }

      # Inject secrets as environment variables at runtime
      env {
        name = "API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.api_key.secret_id
            version = "latest"
          }
        }
      }

      # Non-secret environment variables
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "SERVICE_NAME"
        value = var.service_name
      }
    }
  }

  # Allow unauthenticated access (public API)
  # INTERVIEW: "For internal APIs, I'd remove this and require
  # IAM authentication. For public APIs, auth happens at the
  # application layer (API keys, JWT, etc.)"

  depends_on = [
    google_project_service.apis["run.googleapis.com"],
    google_secret_manager_secret_version.api_key_v1,
  ]
}

# Make the service publicly accessible
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.inference.name
  location = var.region
  project  = var.project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ============================================================
# Outputs
# ============================================================

output "service_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.inference.uri
}

output "service_name_out" {
  description = "Cloud Run service name"
  value       = google_cloud_run_v2_service.inference.name
}
