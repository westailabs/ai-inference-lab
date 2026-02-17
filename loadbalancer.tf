# ============================================================
# Phase 5: Global HTTP(S) Load Balancer for Cloud Run
#
# INTERVIEW TOPIC: "How would you put a Cloud Run service behind a load balancer?"
#
# Key points:
# - Global LB = single anycast IP, traffic routed to nearest region
# - Serverless NEG connects the LB to Cloud Run (no instance groups)
# - URL map defines routing rules (host/path → backend)
# - Google-managed SSL cert = auto-provisioned, auto-renewed
# - Cloud CDN can be enabled on the backend for caching
# - Cloud Armor (WAF) attaches at the backend service level
#
# INTERVIEW DEEP CUT: "The LB stack in GCP is 5 layers":
#   1. Global IP (anycast)
#   2. Forwarding Rule (port → target proxy)
#   3. Target HTTPS Proxy (terminates SSL → URL map)
#   4. URL Map (routing → backend service)
#   5. Backend Service (→ NEG → Cloud Run)
# ============================================================

# --- Enable required API ---
resource "google_project_service" "compute_api" {
  project = var.project_id
  service = "compute.googleapis.com"

  # INTERVIEW: "disable_on_destroy = false prevents accidentally
  # disabling an API that other resources depend on."
  disable_on_destroy = false
}

# --- Serverless Network Endpoint Group (NEG) ---
# INTERVIEW: "A serverless NEG is the bridge between traditional
# GCP load balancing and serverless backends like Cloud Run,
# App Engine, or Cloud Functions. No health checks needed —
# Cloud Run handles that internally."
resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  name    = "${var.service_name}-neg"
  project = var.project_id
  region  = var.region

  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.inference.name
  }

  depends_on = [google_project_service.compute_api]
}

# --- Backend Service ---
# INTERVIEW: "The backend service is where you configure CDN,
# Cloud Armor, session affinity, and connection draining.
# For AI inference, I'd enable CDN only for idempotent GET
# requests and disable it for model inference POST requests."
resource "google_compute_backend_service" "default" {
  name    = "${var.service_name}-backend"
  project = var.project_id

  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  # INTERVIEW: "EXTERNAL_MANAGED is the newer global LB. The legacy
  # EXTERNAL scheme still works but lacks features like advanced
  # traffic management and envoy-based routing."

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run_neg.id
  }

  # Enable Cloud CDN (optional — great for static responses)
  # INTERVIEW: "For inference APIs, CDN helps with repeated identical
  # queries. Set cache_mode to USE_ORIGIN_HEADERS so your app
  # controls cacheability via Cache-Control headers."
  enable_cdn = false # Disabled for dev — enable in prod with cache rules

  # INTERVIEW: "This is where you'd attach a Cloud Armor security
  # policy for WAF, DDoS protection, geo-fencing, rate limiting."
  # security_policy = google_compute_security_policy.waf.id

  log_config {
    enable      = true
    sample_rate = 1.0 # Log all requests in dev, reduce in prod
    # INTERVIEW: "In production, I'd set sample_rate to 0.1-0.5
    # to control logging costs while still catching issues."
  }
}

# --- URL Map (routing rules) ---
# INTERVIEW: "URL maps are GCP's L7 routing. You can route by
# host, path, headers, even query params. For microservices,
# you'd have multiple backend services with path-based routing."
resource "google_compute_url_map" "default" {
  name    = "${var.service_name}-url-map"
  project = var.project_id

  default_service = google_compute_backend_service.default.id

  # INTERVIEW: "For a single service, default_service is enough.
  # In production with multiple services, I'd add host_rule and
  # path_matcher blocks for granular routing."
  #
  # Example (don't apply, just for interview):
  # host_rule {
  #   hosts        = ["api.westailabs.com"]
  #   path_matcher = "api"
  # }
  # path_matcher {
  #   name            = "api"
  #   default_service = google_compute_backend_service.default.id
  #   path_rule {
  #     paths   = ["/v1/inference/*"]
  #     service = google_compute_backend_service.default.id
  #   }
  # }
}

# --- SSL Certificate (Google-managed) ---
# INTERVIEW: "Google-managed certs auto-provision via ACME and
# auto-renew before expiry. Zero maintenance. You just need
# DNS pointing to the LB IP before the cert provisions."
#
# NOTE: Requires a real domain. For the lab, we'll set this up
# but the cert won't provision until DNS is configured.
resource "google_compute_managed_ssl_certificate" "default" {
  name    = "${var.service_name}-cert"
  project = var.project_id

  managed {
    domains = [var.domain_name]
  }
}

# --- HTTPS Proxy (terminates TLS) ---
# INTERVIEW: "The target proxy terminates SSL and forwards
# decrypted traffic to the URL map for routing. For HTTP→HTTPS
# redirect, you'd create a separate HTTP proxy + redirect URL map."
resource "google_compute_target_https_proxy" "default" {
  name    = "${var.service_name}-https-proxy"
  project = var.project_id

  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# --- Global Static IP ---
# INTERVIEW: "A global anycast IP means clients hit the nearest
# Google edge POP. Traffic travels Google's backbone, not the
# public internet. Huge latency win for global users."
resource "google_compute_global_address" "default" {
  name    = "${var.service_name}-ip"
  project = var.project_id
}

# --- Forwarding Rule (ties it all together) ---
# INTERVIEW: "The forwarding rule is the entry point — it maps
# the global IP + port to the target proxy. This is what you'd
# point your DNS A record at."
resource "google_compute_global_forwarding_rule" "https" {
  name    = "${var.service_name}-https-rule"
  project = var.project_id

  target     = google_compute_target_https_proxy.default.id
  ip_address = google_compute_global_address.default.address
  port_range = "443"

  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# --- HTTP → HTTPS Redirect ---
# INTERVIEW: "Always redirect HTTP to HTTPS. This is a separate
# URL map + proxy + forwarding rule — GCP doesn't have a simple
# redirect toggle like AWS ALB listener rules."
resource "google_compute_url_map" "http_redirect" {
  name    = "${var.service_name}-http-redirect"
  project = var.project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  name    = "${var.service_name}-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  name    = "${var.service_name}-http-redirect-rule"
  project = var.project_id

  target     = google_compute_target_http_proxy.redirect.id
  ip_address = google_compute_global_address.default.address
  port_range = "80"

  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ============================================================
# Outputs
# ============================================================

output "load_balancer_ip" {
  description = "Global anycast IP for the load balancer"
  value       = google_compute_global_address.default.address
}

output "lb_url" {
  description = "Load balancer URL (HTTPS)"
  value       = "https://${var.domain_name}"
}

# ============================================================
# INTERVIEW CHEAT SHEET — Load Balancer
#
# Q: "Why use a load balancer in front of Cloud Run?"
# A: Custom domain, SSL termination, Cloud Armor WAF, CDN,
#    multi-region failover, and URL-based routing. Cloud Run's
#    built-in URL works for dev, but production needs these.
#
# Q: "What's the difference between EXTERNAL and EXTERNAL_MANAGED?"
# A: EXTERNAL_MANAGED is the newer envoy-based global LB with
#    advanced traffic management (header-based routing, traffic
#    splitting, mirroring). EXTERNAL is legacy. Always use MANAGED.
#
# Q: "How would you do multi-region?"
# A: Deploy Cloud Run in multiple regions, create a serverless
#    NEG per region, add all as backends. The global LB routes
#    to the nearest healthy region automatically.
#
# Q: "How would you protect this from DDoS?"
# A: Cloud Armor security policy on the backend service. It gives
#    you WAF rules, geo-blocking, rate limiting, and adaptive
#    protection. Google's global LB absorbs volumetric attacks
#    at the edge automatically.
#
# Q: "What about canary deployments?"
# A: Cloud Run has built-in traffic splitting (revisions), or
#    use the URL map with weighted backend services for more
#    control. I'd use revision tags for testing before shifting.
# ============================================================
