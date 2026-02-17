# AI Insights — Change Control & Lessons Learned

> **Project:** AI Inference Lab  
> **Author:** Jason West  
> **Date:** 2026-02-17  
> **Status:** All 6 phases scaffolded, phases 1-5 applied, phase 6 awaiting apply

---

## What Was Built

A production-grade AI inference platform on Google Cloud, managed entirely by Terraform. 29+ resources across 6 incremental phases:

| Phase | Resources Created | Count |
|-------|-------------------|-------|
| 1 — Foundation | Provider config, 6 GCP APIs enabled | 6 |
| 2 — Networking | VPC, subnet, 2 firewall rules | 4 |
| 3 — Cloud Run | Cloud Run v2 service, public IAM binding | 2 |
| 4 — IAM & Secrets | Service account, 3 IAM bindings, secret + version | 5 |
| 5 — Load Balancer | NEG, backend, URL maps (2), SSL cert, proxies (2), global IP, forwarding rules (2), compute API | 11 |
| 6 — Monitoring | Notification channel, uptime check, 4 alert policies, log-based metric | 7 |

---

## Key Decisions

### 1. Cloud Run over GKE
**Decision:** Use Cloud Run for the inference API.  
**Rationale:** Stateless API pattern, auto-scaling to zero, zero cluster management. GKE would be overkill for a single service and adds ~$70/mo for the control plane.  
**Trade-off:** No GPU support on Cloud Run. For real ML inference with large models, GKE with GPU node pools would be necessary.

### 2. Custom VPC with Private Google Access
**Decision:** Create a custom VPC instead of using the default.  
**Rationale:** Explicit control over subnets, firewall rules, and IP ranges. The default VPC has permissive rules and auto-created subnets in every region.  
**Trade-off:** More Terraform code to manage, but essential for production.

### 3. VPC Connector Disabled
**Decision:** Scaffolded the VPC Access Connector but commented it out.  
**Rationale:** Health check failures during apply — likely a quota or billing issue with the f1-micro instances it spins up.  
**Lesson:** VPC connectors have their own health checks and instance requirements. In a real environment, ensure sufficient quota before enabling.

### 4. Local State (No Remote Backend)
**Decision:** Keep Terraform state local for this lab.  
**Rationale:** Solo developer, no team collaboration needed. Remote state adds complexity (GCS bucket, locking) without benefit for learning.  
**Lesson:** Always use remote state in production. State contains secrets and needs locking for concurrent access.

### 5. Scale-to-Zero Configuration
**Decision:** `min_instance_count = 0` with `cpu_idle = true`.  
**Rationale:** Near-zero cost when not actively testing. Free tier friendly.  
**Trade-off:** Cold starts of 2-5 seconds. In production, set `min_instance_count ≥ 1` for latency-sensitive endpoints.

### 6. EXTERNAL_MANAGED Load Balancer
**Decision:** Use the newer `EXTERNAL_MANAGED` scheme over legacy `EXTERNAL`.  
**Rationale:** Envoy-based proxy with advanced features (header-based routing, traffic splitting, mirroring).  
**Lesson:** Some older tutorials/docs reference the legacy scheme. Always check for the `_MANAGED` variant.

### 7. Embedded Runbooks in Alert Documentation
**Decision:** Put step-by-step runbooks directly in alert policy documentation.  
**Rationale:** On-call engineers see actionable steps immediately — no hunting for a wiki page. Reduces MTTR.  
**Lesson:** This is a best practice that interviewers love to hear about.

---

## Lessons Learned

### Terraform-Specific
1. **`for_each` over `count` for APIs** — Using `toset()` with `for_each` creates stable resource addresses. Adding/removing an API doesn't force recreation of others (unlike `count` where index shifts break everything).

2. **`disable_on_destroy = false` is critical** — Without it, `terraform destroy` disables APIs that other resources (or other Terraform workspaces) depend on.

3. **`ignore_changes` for externally managed values** — Secret data and container images are often updated outside Terraform. The `lifecycle` block prevents Terraform from reverting those changes.

4. **Sensitive variables hide from output** — But they're still in state. State file security is just as important as variable handling.

### GCP-Specific
5. **GCP LB is 5 resources, not 1** — Coming from AWS ALB (1 resource + listeners), GCP's decomposed model is verbose but more flexible. Each layer is independently configurable.

6. **Google-managed SSL certs need DNS first** — The cert won't provision until DNS A record points to the LB IP. Plan for propagation time.

7. **Health check source ranges are mandatory** — `130.211.0.0/22` and `35.191.0.0/16` must be allowed through firewall rules or health checks fail silently.

8. **Cloud Run is outside your VPC by default** — It runs on Google's infrastructure. A VPC connector is required to reach private resources. This surprises people coming from traditional compute.

### Process
9. **Incremental phases work** — Building 6 phases incrementally (each adding one concern) made the project learnable and debuggable. Each `terraform apply` added a clear set of resources.

10. **Interview comments in code** — Embedding `INTERVIEW:` comments directly in `.tf` files creates a built-in study guide. The talking points stay connected to the actual implementation.

---

## What I'd Do Differently

1. **Enable VPC connector from the start** — Should have ensured quota/billing before scaffolding it.
2. **Use `terraform workspace`** — Even for a lab, workspaces demonstrate environment isolation knowledge.
3. **Add `terraform-docs`** — Auto-generate input/output documentation from the `.tf` files.
4. **Test with `terratest`** — Infrastructure testing is increasingly expected in interviews.

---

## Risk Register

| Risk | Mitigation | Status |
|------|-----------|--------|
| State file contains secrets | `.gitignore` excludes `*.tfstate*` | ✅ Mitigated |
| Accidental `terraform destroy` in prod | Would add `deletion_protection` | ⚠️ Noted |
| Global IP incurs cost when idle | Tear down after study sessions | ⚠️ Active |
| SSL cert won't provision without DNS | Documented — expected for lab | ✅ Accepted |
