# Copy to terraform.tfvars and fill in real values
# terraform.tfvars is gitignored — never commit secrets

project_id      = "your-gcp-project-id"
region          = "us-central1"
environment     = "dev"
service_name    = "ai-inference-api"
api_key_value   = "your-real-api-key-here"
alert_email     = "ops@yourdomain.com"
domain_name     = "api.yourdomain.com"
container_image = "us-docker.pkg.dev/cloudrun/container/hello"
