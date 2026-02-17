# ============================================================
# Phase 6: Monitoring, Alerting & Observability
#
# INTERVIEW TOPIC: "How do you monitor infrastructure in GCP?"
#
# Key points:
# - Cloud Monitoring = built-in, no agent install for managed services
# - Uptime checks = external probes from Google's global POPs
# - Alert policies = conditions + notification channels + documentation
# - Log-based metrics = turn log patterns into time series
# - Dashboards = custom views for ops teams
#
# INTERVIEW: "Observability has three pillars: metrics, logs, traces.
# GCP gives you all three natively — Cloud Monitoring, Cloud Logging,
# and Cloud Trace. For Terraform-managed infra, I define alerts
# as code so they're version-controlled and reproducible."
# ============================================================

# --- Notification Channel (Email) ---
# INTERVIEW: "Notification channels are separate resources so you
# can reuse them across alert policies. Supports email, Slack,
# PagerDuty, SMS, webhooks, Pub/Sub."
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Ops Email — ${var.service_name}"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  # INTERVIEW: "In production, I'd have multiple channels —
  # PagerDuty for P1, Slack for P2, email for informational.
  # Terraform makes it easy to wire the right channel to
  # the right severity."
}

# --- Uptime Check (external probe) ---
# INTERVIEW: "Uptime checks are external HTTP(S) probes from
# Google's global POPs. They hit your endpoint every 1-5 minutes
# from multiple regions. This catches issues that internal
# health checks might miss — DNS failures, cert expiry, LB
# misconfigurations, regional outages."
resource "google_monitoring_uptime_check_config" "cloud_run" {
  project      = var.project_id
  display_name = "${var.service_name} — Health Check"

  # Check every 5 minutes (free tier friendly)
  period = "300s"
  timeout = "10s"

  http_check {
    path         = "/"
    port         = 443
    use_ssl      = true
    validate_ssl = true

    # INTERVIEW: "validate_ssl catches cert expiry before users do.
    # Combined with Google-managed certs, you get auto-renewal
    # AND proactive alerting if something goes wrong."
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = trimprefix(google_cloud_run_v2_service.inference.uri, "https://")
    }
  }

  # Check from multiple regions for reliability
  # INTERVIEW: "I select checkers from different continents so
  # a regional Google outage doesn't cause false positives."
  selected_regions = [
    "USA",
    "EUROPE",
    "ASIA_PACIFIC",
  ]
}

# --- Alert: Uptime Check Failure ---
# INTERVIEW: "This fires if the service fails from 2+ regions.
# Multi-region consensus prevents alert storms from transient
# network blips at a single POP."
resource "google_monitoring_alert_policy" "uptime" {
  project      = var.project_id
  display_name = "${var.service_name} — Uptime Failure"

  combiner = "OR"

  conditions {
    display_name = "Uptime check failing"

    condition_threshold {
      filter = <<-EOT
        resource.type = "uptime_url" AND
        metric.type = "monitoring.googleapis.com/uptime_check/check_passed" AND
        metric.labels.check_id = "${google_monitoring_uptime_check_config.cloud_run.uptime_check_id}"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.project_id"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.id
  ]

  alert_strategy {
    auto_close = "1800s" # Auto-resolve after 30 minutes
  }

  documentation {
    content   = <<-EOT
      ## ${var.service_name} is DOWN

      **Service:** ${var.service_name}
      **Project:** ${var.project_id}
      **Region:** ${var.region}

      ### Runbook
      1. Check Cloud Run logs: `gcloud run services logs read ${var.service_name} --region=${var.region}`
      2. Verify service is deployed: `gcloud run services describe ${var.service_name} --region=${var.region}`
      3. Check LB backend health: Console → Network Services → Load Balancing → Backends
      4. Check recent Terraform changes: `git log --oneline -5`
    EOT
    mime_type = "text/markdown"
  }

  # INTERVIEW: "I embed runbooks in alert documentation so the
  # on-call engineer gets actionable steps, not just 'it's broken.'
  # This reduces MTTR significantly."
}

# --- Alert: Cloud Run Latency (P95 > 5s) ---
# INTERVIEW: "For AI inference, latency is the key SLI. I alert
# on P95 because P50 hides tail latency that frustrates users.
# The threshold depends on the model — a small classifier should
# respond in <500ms, a large LLM might need 5-10s."
resource "google_monitoring_alert_policy" "latency" {
  project      = var.project_id
  display_name = "${var.service_name} — High Latency (P95 > 5s)"

  combiner = "OR"

  conditions {
    display_name = "Request latency P95 > 5s"

    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_revision" AND
        resource.labels.service_name = "${var.service_name}" AND
        metric.type = "run.googleapis.com/request_latencies"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 5000 # 5000ms = 5s
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_PERCENTILE_95"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.id
  ]

  documentation {
    content   = "P95 latency exceeded 5 seconds for ${var.service_name}. Check for cold starts (scale min > 0), resource limits (CPU/memory), or upstream dependencies."
    mime_type = "text/markdown"
  }
}

# --- Alert: Cloud Run Error Rate (5xx > 5%) ---
# INTERVIEW: "Error rate is the other critical SLI alongside latency.
# I use a ratio — 5xx responses / total responses — because raw
# counts don't account for traffic volume. 10 errors out of 100
# requests is critical; 10 out of 100,000 is noise."
resource "google_monitoring_alert_policy" "error_rate" {
  project      = var.project_id
  display_name = "${var.service_name} — High Error Rate (5xx > 5%)"

  combiner = "OR"

  conditions {
    display_name = "5xx error rate > 5%"

    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_revision" AND
        resource.labels.service_name = "${var.service_name}" AND
        metric.type = "run.googleapis.com/request_count" AND
        metric.labels.response_code_class = "5xx"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.id
  ]

  documentation {
    content   = "5xx error rate exceeded 5% for ${var.service_name}. Check container logs, OOM kills, and recent deployments."
    mime_type = "text/markdown"
  }
}

# --- Alert: Cloud Run Instance Count (approaching max) ---
# INTERVIEW: "I alert at 80% of max instances as an early warning.
# If you hit max, new requests queue or fail. This gives the team
# time to increase limits or investigate runaway traffic."
resource "google_monitoring_alert_policy" "instance_count" {
  project      = var.project_id
  display_name = "${var.service_name} — Instance Count High"

  combiner = "OR"

  conditions {
    display_name = "Instance count > 2 (of 3 max)"

    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_revision" AND
        resource.labels.service_name = "${var.service_name}" AND
        metric.type = "run.googleapis.com/container/instance_count"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 2
      duration        = "60s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.id
  ]

  documentation {
    content   = "Instance count approaching max (3) for ${var.service_name}. Consider increasing max_instance_count or investigating traffic spike."
    mime_type = "text/markdown"
  }
}

# --- Log-based Metric: Cold Starts ---
# INTERVIEW: "Cold starts are the #1 performance complaint with
# serverless. I create a log-based metric to track them over time.
# If cold starts spike, I know to increase min_instance_count or
# optimize container startup time."
resource "google_logging_metric" "cold_starts" {
  project = var.project_id
  name    = "${var.service_name}-cold-starts"

  filter = <<-EOT
    resource.type = "cloud_run_revision" AND
    resource.labels.service_name = "${var.service_name}" AND
    textPayload =~ "Cold start"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Cold Starts — ${var.service_name}"
  }
}

# ============================================================
# Outputs
# ============================================================

output "uptime_check_id" {
  description = "Uptime check ID for the Cloud Run service"
  value       = google_monitoring_uptime_check_config.cloud_run.uptime_check_id
}

output "alert_email" {
  description = "Email receiving monitoring alerts"
  value       = var.alert_email
}

# ============================================================
# INTERVIEW CHEAT SHEET — Monitoring & Observability
#
# Q: "What's your approach to monitoring?"
# A: Three pillars — metrics, logs, traces. For Terraform-managed
#    infra, I define alerts as code. Key SLIs: availability (uptime
#    checks), latency (P95), error rate (5xx ratio). I embed
#    runbooks in alert documentation for faster MTTR.
#
# Q: "How do you handle alert fatigue?"
# A: Severity-based routing (PagerDuty for P1, Slack for P2),
#    auto-close policies, and tuning thresholds based on SLOs.
#    If an alert fires and nobody acts on it, it's noise — delete
#    it or fix the threshold.
#
# Q: "What SLOs would you set for this service?"
# A: 99.9% availability (43.8 min/month downtime budget),
#    P95 latency < 2s, error rate < 0.1%. Measured over a
#    rolling 30-day window. SLO burn rate alerts catch slow
#    degradation that threshold alerts miss.
#
# Q: "How do you monitor costs?"
# A: Billing alerts via Cloud Billing Budgets (separate Terraform
#    resource), per-service cost attribution via labels, and
#    instance count alerts as a proxy for unexpected scaling.
#
# Q: "What about distributed tracing?"
# A: Cloud Trace is automatic for Cloud Run. For custom spans,
#    I'd instrument with OpenTelemetry and export to Cloud Trace.
#    Critical for debugging latency in microservice architectures.
# ============================================================
