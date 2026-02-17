# 🚀 AI Inference Lab — Production GCP Platform with Terraform

A 6-phase, incrementally built AI inference platform on Google Cloud — fully managed by Terraform. Designed as hands-on interview preparation for Senior Systems Engineer roles on Terraform/GCP teams.

> **29+ cloud resources** across networking, compute, security, load balancing, and observability — all defined as code with interview talking points embedded throughout.

---

## Architecture

```
                            ┌─────────────────────────────────┐
                            │         Internet / Users        │
                            └──────────────┬──────────────────┘
                                           │
                                    ┌──────▼──────┐
                                    │  Global IP  │  34.x.x.x (anycast)
                                    │  (anycast)  │
                                    └──────┬──────┘
                                           │
                              ┌────────────▼────────────┐
                              │   Forwarding Rules      │
                              │  :443 → HTTPS Proxy     │
                              │  :80  → HTTP→HTTPS 301  │
                              └────────────┬────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │  Target HTTPS Proxy     │
                              │  (SSL termination)      │
                              │  Google-managed cert    │
                              └────────────┬────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │       URL Map           │
                              │  (L7 routing rules)     │
                              └────────────┬────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │    Backend Service      │
                              │  CDN · Cloud Armor · Logs│
                              └────────────┬────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │   Serverless NEG        │
                              │  (Cloud Run bridge)     │
                              └────────────┬────────────┘
                                           │
                    ┌──────────────────────▼──────────────────────┐
                    │              Cloud Run Service               │
                    │  ┌─────────────────────────────────────────┐ │
                    │  │  ai-inference-api                       │ │
                    │  │  • 1 vCPU / 512Mi RAM                  │ │
                    │  │  • Scale 0→3 instances                 │ │
                    │  │  • Dedicated service account            │ │
                    │  │  • Secrets injected at runtime          │ │
                    │  └─────────────────────────────────────────┘ │
                    └─────────────────────┬───────────────────────┘
                                          │
          ┌───────────────┬───────────────┼───────────────┐
          ▼               ▼               ▼               ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────┐
    │  Secret  │   │   IAM    │   │   VPC    │   │  Monitoring  │
    │ Manager  │   │ (least   │   │ Custom   │   │  • Uptime    │
    │ (API key)│   │ privilege)│  │ + subnet │   │  • Latency   │
    └──────────┘   └──────────┘   └──────────┘   │  • Errors    │
                                                  │  • Scaling   │
                                                  └──────────────┘
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Terraform** | ≥ 1.5.0 | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| **gcloud CLI** | Latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| **GCP Project** | With billing | [console.cloud.google.com](https://console.cloud.google.com) |

```bash
# Authenticate
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

---

## Quick Start

```bash
git clone https://github.com/westailabs/ai-inference-lab.git
cd ai-inference-lab

# Configure your project
cp example.tfvars terraform.tfvars
# Edit terraform.tfvars with your project_id, region, etc.

# Deploy everything
terraform init
terraform plan
terraform apply
```

---

## Phase-by-Phase Walkthrough

### Phase 1 — Foundation (`phase/1-foundation`)

**Files:** `provider.tf` · `versions.tf` · `variables.tf` · `main.tf`

**What it builds:**
- Provider configuration with default labels for cost tracking
- Terraform version pinning (`>= 1.5.0`, Google provider `~> 5.0`)
- Parameterized variables with sensible dev defaults
- Enables 6 GCP APIs declaratively (`for_each` over a set)

**Why it matters:** Every Terraform project needs a solid foundation — pinned versions prevent breaking changes, variables make configs reusable, and declarative API enablement means `terraform apply` on a fresh project just works.

---

### Phase 2 — Networking (`phase/2-networking`)

**File:** `network.tf`

**What it builds:**
- Custom VPC (never use the default in production)
- Subnet (`10.0.1.0/24`) with Private Google Access
- Firewall: allow health checks from GCP LB ranges
- Firewall: allow internal VPC traffic
- VPC Access Connector (scaffolded, disabled — health check quota issue)

**Why it matters:** Custom networking gives explicit control over routing, firewall rules, and access patterns. Private Google Access lets serverless resources reach GCP APIs without public IPs, reducing attack surface.

---

### Phase 3 — Cloud Run (`phase/3-cloud-run`)

**File:** `cloudrun.tf`

**What it builds:**
- Cloud Run v2 service with configurable container image
- Scale-to-zero (0→3 instances) for cost savings
- Resource limits: 1 vCPU / 512Mi RAM
- Secrets injected as environment variables at runtime
- Public access via IAM (`allUsers → roles/run.invoker`)

**Why it matters:** Cloud Run is ideal for stateless AI inference — fully managed, scales to zero, pay per request. Secrets come from Secret Manager (never baked into images), and `cpu_idle=true` releases CPU between requests to reduce cost.

---

### Phase 4 — IAM & Secrets (`phase/4-iam-secrets`)

**Files:** `iam.tf` · `secrets.tf`

**What it builds:**
- Dedicated service account (`ai-inference-runner`)
- Least-privilege IAM: secretAccessor + logWriter + metricWriter
- Secret Manager secret with `ignore_changes` on secret data
- Sensitive variable handling (`sensitive = true`)

**Why it matters:** The default compute service account has Editor role — way too broad. Each service gets its own SA with only the permissions it needs. Secret values are managed outside Terraform (via gcloud/CI/CD) so they never appear in state files.

---

### Phase 5 — Global Load Balancer (`phase/5-load-balancer`)

**File:** `loadbalancer.tf`

**What it builds:**
- Global anycast IP address
- Serverless NEG bridging the LB to Cloud Run
- Backend service with logging (sample rate 1.0 for dev)
- URL map for L7 routing
- Google-managed SSL certificate (auto-provisioned, auto-renewed)
- HTTPS proxy for SSL termination
- HTTP→HTTPS redirect (301 Moved Permanently)

**Why it matters:** The 5-layer GCP LB stack (IP → Forwarding Rule → Proxy → URL Map → Backend) gives you custom domains, SSL, Cloud Armor WAF, CDN, and multi-region routing. Cloud Run's built-in URL works for dev but production needs these controls.

**The 5 layers:**
1. **Global IP** — anycast, nearest Google edge POP
2. **Forwarding Rule** — port → target proxy
3. **Target HTTPS Proxy** — terminates SSL → URL map
4. **URL Map** — routing → backend service
5. **Backend Service** — → NEG → Cloud Run

---

### Phase 6 — Monitoring & Alerting (`phase/6-monitoring`)

**File:** `monitoring.tf`

**What it builds:**
- Email notification channel (extensible to PagerDuty/Slack)
- Global uptime check (probes from USA, Europe, Asia Pacific)
- Alert: uptime failure (multi-region consensus)
- Alert: P95 latency > 5s
- Alert: 5xx error rate > 5%
- Alert: instance count approaching max (scaling pressure)
- Log-based metric: cold start tracking
- Embedded runbooks in alert documentation

**Why it matters:** Observability is three pillars — metrics, logs, traces. Alerts defined as code are version-controlled and reproducible. Embedded runbooks reduce MTTR by giving on-call engineers actionable steps, not just "it's broken."

---

## Cost Estimate

This lab is designed to stay within **GCP Free Tier** for learning:

| Resource | Free Tier | Lab Usage |
|----------|-----------|-----------|
| Cloud Run | 2M requests/mo, 360k vCPU·s | Minimal (scale-to-zero) |
| Secret Manager | 6 active versions | 1 secret, 1 version |
| Cloud Monitoring | 500 free time series | ~10 time series |
| Load Balancer | 5 forwarding rules | 2 rules |
| VPC / Firewall | Free | Free |
| **Global IP** | **$0.01/hr while unattached** | ~$7/mo if idle |

---

## 💸 Teardown / Cost Control

### What costs money when idle

| Resource | Idle Cost | Why |
|----------|-----------|-----|
| **Global Static IP** | ~$0.01/hr (~$7/mo) | Charged when reserved, even if no traffic |
| **LB Forwarding Rules** (×2) | ~$0.025/hr each (~$36/mo total) | Per-rule hourly charge |
| **SSL Certificate** | Free | Google-managed, no charge |
| **Cloud Run** | **Free when idle** | Scale-to-zero = $0 with no requests |
| **VPC / Firewall / Subnet** | **Free** | No charge for network resources |
| **Secret Manager** | **Free** | Under 6 active versions = free tier |
| **Monitoring / Alerts** | **Free** | Under 500 time series = free tier |
| **IAM / Service Account** | **Free** | No charge |

> **Bottom line:** The load balancer stack is the only real cost (~$43/mo if left running). Everything else is free at this scale.

### Option 1: Full teardown (recommended after study sessions)

```bash
cd ~/projects/gcp_projects/ai-inference-lab
terraform destroy
# Type "yes" when prompted — destroys ALL 29+ resources
```

Rebuild anytime with `terraform apply` — takes ~3 minutes.

### Option 2: Partial teardown (destroy only the expensive LB)

Keep Cloud Run, VPC, IAM, secrets, and monitoring (all free) but remove the load balancer:

```bash
# Destroy only the LB resources (saves ~$43/mo)
terraform destroy \
  -target=google_compute_global_forwarding_rule.https \
  -target=google_compute_global_forwarding_rule.http_redirect \
  -target=google_compute_target_https_proxy.default \
  -target=google_compute_target_http_proxy.redirect \
  -target=google_compute_url_map.default \
  -target=google_compute_url_map.http_redirect \
  -target=google_compute_backend_service.default \
  -target=google_compute_region_network_endpoint_group.cloud_run_neg \
  -target=google_compute_managed_ssl_certificate.default \
  -target=google_compute_global_address.default
```

Your Cloud Run service stays live at its `*.run.app` URL — just no custom domain or LB.

To rebuild the LB later:
```bash
terraform apply  # Terraform recreates only the missing resources
```

### Option 3: Verify what's running (cost audit)

```bash
# Check current Terraform resource count
terraform state list | wc -l

# Check the global IP (this is the $7/mo one)
terraform state show google_compute_global_address.default 2>/dev/null && \
  echo "⚠️  Global IP is active — costs ~$0.01/hr" || \
  echo "✅ No global IP — no charge"

# Check forwarding rules (these are the $36/mo ones)
terraform state list | grep forwarding_rule && \
  echo "⚠️  Forwarding rules active — costs ~$0.025/hr each" || \
  echo "✅ No forwarding rules — no charge"
```

> 💡 **Pro tip:** Set a calendar reminder or billing alert at $5/mo so you catch forgotten resources early.

---

## Architecture Decisions & Trade-offs

| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| Cloud Run over GKE | Stateless API, auto-scaling, zero ops | No GPU support, cold starts |
| Custom VPC over default | Explicit firewall control, Private Google Access | More config to manage |
| Scale-to-zero | Near-zero cost when idle | Cold start latency (~2-5s) |
| `cpu_idle = true` | Reduces cost between requests | Higher latency for bursty traffic |
| Google-managed SSL | Zero maintenance, auto-renewal | Requires DNS pointing to LB |
| `EXTERNAL_MANAGED` LB | Envoy-based, advanced routing | Newer — less community docs |
| Local Terraform state | Simple for solo dev | No locking, no team collaboration |
| VPC Connector disabled | Avoided health check quota issue | Cloud Run can't reach private VPC resources |

---

## Interview Talking Points — Study Guide

Extracted from `INTERVIEW:` comments across all `.tf` files:

### 🏗️ Foundation & Providers
- Provider block sets project/region defaults — avoids repetition
- Pin provider versions (`~> 5.0`) to prevent breaking changes
- `required_version` prevents running with incompatible Terraform
- Start with local state for prototyping, migrate to GCS for teams
- Variables with descriptions = self-documenting code

### 🌐 Networking
- **Always** custom VPC — never use the default in production
- `auto_create_subnetworks = false` for explicit subnet control
- Private Google Access lets resources reach GCP APIs without external IPs
- Default deny-all ingress, explicit allow rules scoped by tag/SA
- VPC connectors bridge serverless (Cloud Run) into private networks

### 🐳 Cloud Run & Containers
- Cloud Run = fully managed, scales to zero, pay per request
- Cloud Run vs GKE: Cloud Run for stateless APIs, GKE for complex workloads
- Tune concurrency based on model size (classifier: ~80, LLM: 1-4)
- `cpu_idle=true` releases CPU when not processing — reduces cost
- For internal APIs: require IAM auth. For public: auth at app layer

### 🔐 IAM & Security
- **Never use the default compute service account** (has Editor role)
- Each service gets its own SA with only needed permissions
- Secret Manager stores secrets; Terraform creates the container
- `ignore_changes` on secret_data prevents overwriting rotated secrets
- Mark variables `sensitive = true` to hide from plan output

### ⚖️ Load Balancing
- **5-layer stack:** IP → Forwarding Rule → Proxy → URL Map → Backend
- Global anycast IP = traffic hits nearest Google edge POP
- Serverless NEG bridges traditional LB to Cloud Run
- `EXTERNAL_MANAGED` (envoy-based) over legacy `EXTERNAL`
- Cloud Armor attaches at backend service level for WAF/DDoS
- Multi-region: deploy Cloud Run per region, NEG per region, LB routes automatically
- Canary: Cloud Run revision traffic splitting or URL map weighted backends

### 📊 Monitoring & Observability
- Three pillars: metrics, logs, traces
- Key SLIs: availability (uptime checks), latency (P95), error rate (5xx ratio)
- Alert on P95 latency — P50 hides tail latency
- Use error **ratios**, not raw counts (10/100 ≠ 10/100,000)
- Embed runbooks in alert documentation for faster MTTR
- Alert at 80% of max instances as early warning
- Cold starts: track with log-based metrics, mitigate with `min_instance_count > 0`
- SLOs: 99.9% availability, P95 < 2s, error rate < 0.1% over 30-day window
- Severity routing: PagerDuty for P1, Slack for P2, email for info

### 💡 Production Upgrades (What I'd Add Next)
- Remote state backend (GCS with locking)
- Cloud Armor WAF security policy
- Cloud CDN on backend service (for idempotent GET requests)
- Multi-region Cloud Run deployment
- Artifact Registry for container images
- CI/CD pipeline for Terraform (atlantis or GitHub Actions)
- Billing budget alerts via Terraform
- OpenTelemetry instrumentation for distributed tracing

---

## Project Structure

```
ai-inference-lab/
├── provider.tf          # GCP provider config + default labels
├── versions.tf          # Terraform + provider version pins
├── variables.tf         # Parameterized inputs (project, region, etc.)
├── main.tf              # Phase 1: API enablement
├── network.tf           # Phase 2: VPC, subnets, firewalls
├── cloudrun.tf          # Phase 3: Cloud Run service
├── iam.tf               # Phase 4: Service accounts, IAM bindings
├── secrets.tf           # Phase 4: Secret Manager
├── loadbalancer.tf      # Phase 5: Global HTTPS LB (11 resources)
├── monitoring.tf        # Phase 6: Alerts, uptime checks, metrics
├── example.tfvars       # Safe-to-share variable template
├── docs/
│   ├── architecture.md  # Detailed resource reference
│   └── AI_INSIGHTS.md   # Change control & lessons learned
└── .gitignore           # Ignores .tfstate, .tfvars, .terraform/
```

---

## Branch Structure

Each phase is preserved as a branch for step-by-step review:

```
main                    ← Full project (all 6 phases)
phase/1-foundation      ← Provider, versions, variables, APIs
phase/2-networking      ← VPC, subnet, firewalls
phase/3-cloud-run       ← Cloud Run service deployment
phase/4-iam-secrets     ← IAM + Secret Manager
phase/5-load-balancer   ← Global HTTPS load balancer
phase/6-monitoring      ← Alerts, uptime checks, metrics
```

---

## License

MIT — built for learning. Use it, fork it, make it yours.
