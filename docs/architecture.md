# Architecture Reference

> Detailed resource relationships for the AI Inference Lab platform.

---

## Resource Dependency Graph

```
google_project_service.apis["compute.googleapis.com"]
  └─► google_compute_network.main (VPC)
        ├─► google_compute_subnetwork.main
        ├─► google_compute_firewall.allow_health_checks
        └─► google_compute_firewall.allow_internal

google_project_service.apis["secretmanager.googleapis.com"]
  └─► google_secret_manager_secret.api_key
        └─► google_secret_manager_secret_version.api_key_v1

google_project_service.apis["run.googleapis.com"]
  └─► google_cloud_run_v2_service.inference
        │     ├── uses: google_service_account.cloud_run (template.service_account)
        │     └── uses: google_secret_manager_secret.api_key (env.API_KEY)
        ├─► google_cloud_run_v2_service_iam_member.public
        └─► google_compute_region_network_endpoint_group.cloud_run_neg
              └─► google_compute_backend_service.default
                    └─► google_compute_url_map.default
                          └─► google_compute_target_https_proxy.default
                                │     └── uses: google_compute_managed_ssl_certificate.default
                                └─► google_compute_global_forwarding_rule.https
                                      └── uses: google_compute_global_address.default

google_compute_url_map.http_redirect
  └─► google_compute_target_http_proxy.redirect
        └─► google_compute_global_forwarding_rule.http_redirect
              └── uses: google_compute_global_address.default (shared IP)

google_service_account.cloud_run
  ├─► google_project_iam_member.cloud_run_secret_access
  ├─► google_project_iam_member.cloud_run_logging
  └─► google_project_iam_member.cloud_run_monitoring

google_cloud_run_v2_service.inference
  ├─► google_monitoring_uptime_check_config.cloud_run
  │     └─► google_monitoring_alert_policy.uptime
  ├─► google_monitoring_alert_policy.latency
  ├─► google_monitoring_alert_policy.error_rate
  ├─► google_monitoring_alert_policy.instance_count
  └─► google_logging_metric.cold_starts

google_monitoring_notification_channel.email
  └── used by: all 4 alert policies
```

---

## Resource Inventory

### Phase 1 — Foundation

| Resource | Type | Name |
|----------|------|------|
| GCP APIs (×6) | `google_project_service` | run, compute, secretmanager, iam, monitoring, artifactregistry |

### Phase 2 — Networking

| Resource | Type | Name/CIDR |
|----------|------|-----------|
| VPC | `google_compute_network` | `ai-inference-vpc` (custom, no auto subnets) |
| Subnet | `google_compute_subnetwork` | `ai-inference-subnet` / `10.0.1.0/24` |
| Firewall | `google_compute_firewall` | `allow-health-checks` (TCP:8080 from GCP LB ranges) |
| Firewall | `google_compute_firewall` | `allow-internal` (all protocols from `10.0.0.0/8`) |

### Phase 3 — Cloud Run

| Resource | Type | Config |
|----------|------|--------|
| Service | `google_cloud_run_v2_service` | `ai-inference-api` / 1 vCPU / 512Mi / 0→3 instances |
| IAM | `google_cloud_run_v2_service_iam_member` | `allUsers → roles/run.invoker` |

### Phase 4 — IAM & Secrets

| Resource | Type | Details |
|----------|------|---------|
| Service Account | `google_service_account` | `ai-inference-runner` |
| IAM Binding | `google_project_iam_member` | `roles/secretmanager.secretAccessor` |
| IAM Binding | `google_project_iam_member` | `roles/logging.logWriter` |
| IAM Binding | `google_project_iam_member` | `roles/monitoring.metricWriter` |
| Secret | `google_secret_manager_secret` | `ai-inference-api-key` (auto replication) |
| Secret Version | `google_secret_manager_secret_version` | v1 (lifecycle: ignore secret_data changes) |

### Phase 5 — Load Balancer

| Resource | Type | Details |
|----------|------|---------|
| Serverless NEG | `google_compute_region_network_endpoint_group` | Bridges LB → Cloud Run |
| Backend Service | `google_compute_backend_service` | `EXTERNAL_MANAGED`, logging enabled |
| URL Map | `google_compute_url_map` | Default route → backend |
| SSL Certificate | `google_compute_managed_ssl_certificate` | Google-managed for `api.westailabs.com` |
| HTTPS Proxy | `google_compute_target_https_proxy` | SSL termination |
| Global IP | `google_compute_global_address` | Anycast IP |
| HTTPS Forwarding Rule | `google_compute_global_forwarding_rule` | `:443 → HTTPS proxy` |
| HTTP Redirect URL Map | `google_compute_url_map` | 301 → HTTPS |
| HTTP Proxy | `google_compute_target_http_proxy` | For redirect |
| HTTP Forwarding Rule | `google_compute_global_forwarding_rule` | `:80 → HTTP proxy` |

### Phase 6 — Monitoring

| Resource | Type | Details |
|----------|------|---------|
| Notification Channel | `google_monitoring_notification_channel` | Email alerts |
| Uptime Check | `google_monitoring_uptime_check_config` | HTTPS / 5min / 3 regions |
| Alert: Uptime | `google_monitoring_alert_policy` | Fires on multi-region failure |
| Alert: Latency | `google_monitoring_alert_policy` | P95 > 5s for 5 minutes |
| Alert: Error Rate | `google_monitoring_alert_policy` | 5xx > 5% for 5 minutes |
| Alert: Scaling | `google_monitoring_alert_policy` | Instance count > 2 of 3 max |
| Log Metric | `google_logging_metric` | Cold start counter |

---

## Network Flow

```
Client Request
  │
  ▼
Google Edge POP (nearest to client)
  │  Global anycast routes to nearest POP
  ▼
Global Forwarding Rule (:443)
  │  Matches IP:port, forwards to proxy
  ▼
Target HTTPS Proxy
  │  Terminates TLS (Google-managed cert)
  │  Decrypts → passes to URL map
  ▼
URL Map
  │  Routes based on host/path rules
  │  (default: all traffic → backend service)
  ▼
Backend Service
  │  Applies: logging, (CDN), (Cloud Armor)
  │  Selects: serverless NEG
  ▼
Serverless NEG
  │  Routes to Cloud Run service
  ▼
Cloud Run Instance
  │  Container handles request
  │  Reads secrets from Secret Manager
  │  Writes logs/metrics via IAM roles
  ▼
Response (reverse path)
```

---

## IAM Relationships

```
google_service_account: ai-inference-runner
  │
  ├── roles/secretmanager.secretAccessor
  │     └── Can read: ai-inference-api-key
  │
  ├── roles/logging.logWriter
  │     └── Can write: Cloud Logging
  │
  └── roles/monitoring.metricWriter
        └── Can write: Cloud Monitoring metrics

Cloud Run Service
  └── Runs as: ai-inference-runner (not default compute SA)

Public Access
  └── allUsers → roles/run.invoker (unauthenticated access)
```

---

## Outputs Reference

| Output | Source | Value |
|--------|--------|-------|
| `enabled_apis` | main.tf | List of enabled API service names |
| `vpc_name` | network.tf | `ai-inference-vpc` |
| `subnet_cidr` | network.tf | `10.0.1.0/24` |
| `service_url` | cloudrun.tf | Cloud Run HTTPS URL |
| `service_name_out` | cloudrun.tf | `ai-inference-api` |
| `cloud_run_service_account` | iam.tf | SA email address |
| `secret_name` | secrets.tf | `ai-inference-api-key` |
| `load_balancer_ip` | loadbalancer.tf | Global anycast IP |
| `lb_url` | loadbalancer.tf | `https://api.westailabs.com` |
| `uptime_check_id` | monitoring.tf | Uptime check resource ID |
| `alert_email` | monitoring.tf | Alert notification email |
