# ── iam.tf ────────────────────────────────────────────────────────────────────
# Creates a dedicated service account for GKE nodes and grants it only the
# permissions it actually needs — this is the "principle of least privilege".
#
# Why not use the Compute Engine default SA?
# The default SA has Editor-level access to the whole project, which is far
# too broad. If a node were compromised, the blast radius would be the entire
# GCP project. Our custom SA limits damage to: pull images + write logs/metrics.

# Create the service account identity
resource "google_service_account" "gke_sa" {
  account_id   = "gke-node-sa"                  # becomes gke-node-sa@PROJECT.iam.gserviceaccount.com
  display_name = "GKE Node Service Account"
  description  = "Least-privilege SA for GKE worker nodes"
  project      = var.project_id
}

# Grant: pull container images from Artifact Registry
# Nodes need this to download the app image we push in Phase 2
resource "google_project_iam_member" "gke_sa_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# Grant: write application and system logs to Cloud Logging
# Without this, kubectl logs and Cloud Console logs would be empty
resource "google_project_iam_member" "gke_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# Grant: write custom metrics to Cloud Monitoring
# Required for the GKE metrics agent (kubelet, node exporters) to function
resource "google_project_iam_member" "gke_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# Grant: read monitoring data — needed for GKE's built-in health checks
resource "google_project_iam_member" "gke_sa_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}
