# AI Inference Lab — Terraform + GCP

Production-grade AI inference platform on Google Cloud, built incrementally with Terraform.

## Phases

| Branch | Phase | Resources |
|--------|-------|-----------|
| `phase/1-foundation` | API enablement, provider config | versions, provider, variables, APIs |
| `phase/2-networking` | VPC, subnet, firewalls | network.tf |
| `phase/3-cloud-run` | Cloud Run service | cloudrun.tf |
| `phase/4-iam-secrets` | Service account, IAM, Secret Manager | iam.tf, secrets.tf |
| `phase/5-load-balancer` | Global HTTP(S) LB, SSL, NEG | loadbalancer.tf |
| `phase/6-monitoring` | Alerts, uptime checks, log metrics | monitoring.tf |

## Usage

```bash
# Switch to any phase to see what changed
git checkout phase/3-cloud-run
git diff phase/2-networking..phase/3-cloud-run

# Apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Interview Notes
Every .tf file contains `INTERVIEW:` comments with talking points and cheat sheets.
