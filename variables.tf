# ============================================================
# INTERVIEW TOPIC: "How do you parameterize Terraform configs?"
#
# Key points:
# - Variables make configs reusable across environments
# - Use descriptions for self-documenting code
# - Sensitive vars (API keys) should use sensitive = true
# - Default values for dev, override for prod via .tfvars
# ============================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "ai-engineering-lab"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment label (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "ai-inference-api"
}

variable "api_key_value" {
  description = "API key for the inference service (set via tfvars or env, never hardcode)"
  type        = string
  sensitive   = true # INTERVIEW: prevents this from showing in plan/apply output
  default     = "placeholder-rotate-me"
}

variable "alert_email" {
  description = "Email address for monitoring alert notifications"
  type        = string
  default     = "jason@westailabs.com"
  # INTERVIEW: "In production, this would be a team alias or
  # PagerDuty integration, not a personal email."
}

variable "domain_name" {
  description = "Domain name for the SSL certificate and load balancer"
  type        = string
  default     = "api.westailabs.com"
  # INTERVIEW: "The cert won't provision until DNS points here.
  # In production, I'd use a subdomain so the main site stays separate."
}

variable "container_image" {
  description = "Container image for Cloud Run service"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
  # Using Google's sample container for testing
  # In production: your own image from Artifact Registry
}
