# Terraform Troubleshooting — Interview Reference

## State Out of Sync (409 "Entity Already Exists")

**Scenario:** You Ctrl+C during `terraform apply`, or a resource was created manually outside Terraform. GCP says it exists, Terraform doesn't know about it.

**Error:**
```
Error: Error creating Connector: googleapi: Error 409: Requested entity already exists
```

**Fix — Import into state:**
```bash
terraform import <resource_type>.<name> <gcp_resource_id>

# Example:
terraform import google_vpc_access_connector.main \
  projects/ai-engineering-lab/locations/us-central1/connectors/ai-vpc-connector
```

**Verify:**
```bash
terraform plan -out=tfplan
# Should show: 0 to add, 0 to change, 0 to destroy
```

**Interview answer:** "When state gets out of sync with reality, I use `terraform import` to bring existing resources into state, or `terraform state rm` to remove phantom entries. I never manually edit the state file — that's a recipe for corruption."

---

## Other Common State Issues

### Resource exists in state but was deleted manually
```bash
terraform state rm <resource_type>.<name>
# Then terraform plan will recreate it
```

### View what's in state
```bash
terraform state list          # All resources
terraform state show <name>   # Details of one resource
```

### Force unlock stuck state (remote backends)
```bash
terraform force-unlock <lock_id>
# Only when you're SURE no other apply is running
```

---

## Unsupported Argument Error

**Scenario:** Terraform plan fails with "An argument named X is not expected here." The argument exists in docs but your provider version doesn't support it.

**Error:**
```
Error: Unsupported argument
  on cloudrun.tf line 21, in resource "google_cloud_run_v2_service" "inference":
  21: deletion_protection = false
  An argument named "deletion_protection" is not expected here.
```

**Cause:** Provider version pinned to an older release that doesn't include the argument. The `~> 5.0` constraint allows 5.x but not 6.x.

**Fix options:**
1. **Remove the argument** — keep the concept as a comment for documentation
2. **Update provider version** — change constraint in `versions.tf` and run `terraform init -upgrade`
3. **Check provider changelog** — find which version introduced the argument

```bash
# Check current provider version
terraform providers

# Upgrade provider
terraform init -upgrade
```

**Interview answer:** "Provider version pinning is a tradeoff — stability vs features. I pin with `~>` to allow patches but not majors. When I hit unsupported arguments, I check the changelog to see if it's worth upgrading or if I should defer."

---

## IAM Propagation Race Condition (Permission Denied on Secret)

**Scenario:** Terraform creates an IAM role binding and immediately tries to use it. GCP hasn't propagated the permission yet, so the resource creation fails.

**Error:**
```
Error: Error waiting to create Service: Permission denied on secret:
projects/PROJECT/secrets/SECRET for Revision service account SA@PROJECT.iam.gserviceaccount.com.
The service account used must be granted the 'Secret Manager Secret Accessor' role
```

**Cause:** GCP IAM is **eventually consistent** — role bindings can take up to 60 seconds to propagate. Terraform created the IAM binding and Cloud Run service in parallel, and Cloud Run tried to read the secret before IAM caught up.

**Fix:**
```bash
# Just re-run — the IAM binding is already in place
terraform plan -out=tfplan
terraform apply tfplan
```

**Prevention options:**
1. Add `depends_on` to force ordering (Cloud Run waits for IAM)
2. Add a `time_sleep` resource between IAM and the consumer (hacky but works)
3. In CI/CD, add retry logic on apply

```hcl
# Option 1: Explicit dependency
resource "google_cloud_run_v2_service" "inference" {
  depends_on = [
    google_project_iam_member.cloud_run_secret_access,
  ]
}

# Option 2: Sleep (not ideal but sometimes necessary)
resource "time_sleep" "wait_for_iam" {
  depends_on      = [google_project_iam_member.cloud_run_secret_access]
  create_duration = "30s"
}
```

**Interview answer:** "GCP IAM is eventually consistent. When you create a role binding and immediately consume it, you can hit a race condition. I handle this with explicit `depends_on` ordering in Terraform, or retry logic in CI/CD pipelines. A second apply always resolves it because IAM has propagated by then."

---

## Resource Stuck in ERROR State (VPC Connector / Ctrl+C Aftermath)

**Scenario:** You Ctrl+C during apply, and a resource was partially created. Terraform retries fail because the resource exists in GCP but is in an error state.

**Error:**
```
Error: Error waiting to create Service: Failed to prepare VPC connector. Please try again later
```

**Diagnosis — Use gcloud to check actual resource state:**
```bash
gcloud compute networks vpc-access connectors describe CONNECTOR_NAME \
  --region=REGION --project=PROJECT_ID
```

If you see `state: ERROR`, the resource is busted and needs to be destroyed and recreated.

**Fix:**
```bash
# Destroy just the broken resource
terraform destroy -target=google_vpc_access_connector.main -auto-approve

# Re-plan and apply everything
terraform plan -out=tfplan
terraform apply tfplan
```

**Key lesson:** When Terraform errors are vague ("try again later"), **use `gcloud describe` to check actual resource state**. Terraform only knows what's in its state file — `gcloud` shows you reality.

**Interview answer:** "When Terraform gives vague errors, I go directly to the cloud provider CLI to inspect resource state. Terraform's error messages don't always tell the full story. In this case, a VPC connector was stuck in ERROR state from an interrupted apply — `gcloud describe` showed the real problem, and a targeted destroy + recreate fixed it."

---

## Prevention

- **Always let `apply` finish** — don't Ctrl+C unless absolutely necessary
- **Use `-out=tfplan`** — saved plans catch drift before apply
- **Remote state (GCS/S3)** — locking prevents concurrent applies
- **`terraform plan` before every apply** — never blind-apply
- **CI/CD gates** — plan in PR, apply on merge
