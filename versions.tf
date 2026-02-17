# ============================================================
# INTERVIEW TOPIC: "How do you manage Terraform versions and providers?"
# 
# Key points to mention:
# - Pin provider versions to avoid breaking changes
# - required_version prevents running with incompatible Terraform
# - Backend config separates state from code
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Phase 1: Local backend first, migrate to GCS later
  # INTERVIEW: "I start with local state for prototyping, 
  # then migrate to remote state (GCS/S3) for team collaboration"
  # 
  # backend "gcs" {
  #   bucket = "ai-engineering-lab-tfstate"
  #   prefix = "ai-inference-lab"
  # }
}
