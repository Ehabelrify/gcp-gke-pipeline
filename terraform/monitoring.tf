# ── monitoring.tf ─────────────────────────────────────────────────────────────
# GCP Cloud Monitoring resources.
# GKE already streams logs and metrics to Cloud Logging/Monitoring by default —
# these resources add application-level visibility on top of that.

# ── Uptime Check ──────────────────────────────────────────────────────────────
# An uptime check pings our app's /health endpoint every 60 seconds from
# multiple GCP regions. If it fails, Cloud Monitoring can alert us.
# This proves the app is reachable from the public internet end-to-end.
resource "google_monitoring_uptime_check_config" "fastapi_health" {
  project      = var.project_id
  display_name = "FastAPI /health uptime check"
  timeout      = "10s"   # fail the check if no response within 10 seconds
  period       = "60s"   # run the check every 60 seconds

  http_check {
    path         = "/health"   # the endpoint we defined in main.py
    port         = "80"        # the LoadBalancer listens on port 80
    use_ssl      = false       # no TLS on our demo LoadBalancer
    validate_ssl = false
  }

  # Check from a single region to stay within free tier limits.
  # Production uptime checks use 3+ regions for global coverage.
  monitored_resource {
    type = "uptime_url"   # built-in GCP resource type for URL-based checks
    labels = {
      project_id = var.project_id
      host       = "34.72.172.168"   # external IP of the GKE LoadBalancer Service
    }
  }
}

# ── Log-based Metric ──────────────────────────────────────────────────────────
# Counts HTTP 5xx errors from our FastAPI app logs.
# Cloud Logging captures all stdout/stderr from GKE pods automatically —
# we just define a filter to extract the error count as a metric.
resource "google_logging_metric" "fastapi_5xx_errors" {
  project = var.project_id
  name    = "fastapi-5xx-errors"
  filter  = "resource.type=\"k8s_container\" AND resource.labels.container_name=\"fastapi-app\" AND textPayload=~\"HTTP/1.1 5\""

  metric_descriptor {
    metric_kind = "DELTA"    # counts events in each reporting interval
    value_type  = "INT64"    # integer count
    unit        = "1"
    # No label extractors — we just need a total count of 5xx errors,
    # not broken down by status code. Labels require a matching label_extractors
    # block mapping log fields to label values, which adds complexity for no benefit here.
  }
}
