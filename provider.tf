# ============================================================
# INTERVIEW TOPIC: "Walk me through your provider configuration"
#
# Key points:
# - Provider block configures authentication and defaults
# - project/region set here avoid repeating in every resource
# - Labels/tags for cost tracking and resource management
# ============================================================

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "ai-inference-lab"
  }
}
