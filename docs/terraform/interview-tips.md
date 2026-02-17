# Terraform & GCP — Interview Tips

Quick-reference talking points collected during hands-on lab work.

---

## Workflow

**"What's your Terraform workflow?"**
> "Always plan → review → apply. I never skip the plan step. The saved plan file is my contract — I know exactly what's going to happen before I commit. In CI/CD, the PR triggers plan, merge triggers apply using the saved plan artifact."

**"Why always re-plan before apply?"**
> "State can drift between runs — someone else applied, GCP auto-healed, or a previous apply was interrupted. Re-planning is cheap (just API reads) and catches surprises."

---

## State Management

**"How do you manage Terraform state?"**
> "Local state for prototyping, remote state (GCS/S3) for teams. Remote gives you locking, versioning, and shared access. I never manually edit state files."

**"What do you do when state gets out of sync?"**
> "terraform import to bring existing resources into state, terraform state rm to remove phantom entries. Never manually edit the state file."

---

## Verification

**"How do you verify Terraform actually did what you expected?"**
> "I cross-reference three sources: `terraform state list` shows what Terraform thinks exists, `gcloud describe` shows actual resource state, and the GCP Console gives a visual confirmation. Trust but verify."

**"When Terraform errors are vague?"**
> "I go directly to the cloud provider CLI. `gcloud describe` on the resource usually reveals the real problem — Terraform's error messages don't always tell the full story."

---

## Project Structure

**"How do you structure Terraform projects?"**
> "For small projects, flat directory with files split by concern (network.tf, iam.tf, etc.). For production, modules for reusability plus separate environment directories with their own state backends and tfvars. Each environment gets its own apply — dev changes never accidentally hit prod."

**"Are file names significant?"**
> "No — Terraform merges all .tf files in a directory into one config. Naming is pure convention for readability. I split by concern so PRs are self-documenting."

---

## IAM & Security

**"How do you handle IAM?"**
> "Dedicated service account per service. Never use the default compute SA — it has Editor role which violates least privilege. Each service gets only the permissions it needs."

**"How do you manage secrets?"**
> "Never hardcode secrets in .tf files. I create the Secret Manager resource in Terraform but set values through CLI or CI/CD. Secret values should never appear in state or plan output. I use `sensitive = true` on variables."

---

## GCP Specifics

**"GCP IAM is eventually consistent"**
> "Role bindings can take up to 60 seconds to propagate. If you create a binding and immediately use it, you can hit a race condition. I handle this with explicit `depends_on` or retry logic in CI/CD."

**"Health check IP ranges"**
> "GCP load balancers probe from fixed CIDRs (130.211.0.0/22 and 35.191.0.0/16). You must whitelist these in firewall rules or the LB marks everything unhealthy."

**"Cloud Run vs GKE"**
> "Cloud Run for stateless APIs that need to scale to zero. GKE for complex workloads with state, custom networking, or specific scheduling needs. Cloud Run is simpler and cheaper for most inference endpoints."

**"VPC Connector"**
> "Cloud Run runs outside your VPC by default. The Serverless VPC Connector bridges it into your private network for accessing internal resources."

---

## Production Best Practices

**"What would you do differently in production?"**
> "Modules for reusability, separate environments with isolated state, remote backend with locking, deletion_protection on critical resources, CI/CD gates (plan on PR, apply on merge), and monitoring/alerting on infrastructure drift."

**"How do you handle the -target flag?"**
> "Only for recovery situations — fixing broken resources or imports. Never for routine use. It creates partial plans that can miss dependencies."
