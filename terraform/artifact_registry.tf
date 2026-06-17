# ── artifact_registry.tf ──────────────────────────────────────────────────────
# Creates a Docker image repository in Google Artifact Registry.
# This is where we push our FastAPI container image, and where GKE nodes
# pull it from when deploying pods.
#
# Artifact Registry is the successor to Container Registry — it supports
# multiple formats (Docker, npm, Maven) and has finer-grained IAM controls.

resource "google_artifact_registry_repository" "app_repo" {
  project       = var.project_id
  location      = var.region          # must be a region, not a zone
  repository_id = "app-repo"          # becomes part of the image URL
  format        = "DOCKER"            # we're storing Docker images
  description   = "Docker image repository for the FastAPI application"
}

# The full image URL pattern for pushing/pulling will be:
# us-central1-docker.pkg.dev/gcp-gke-pipeline-ehab/app-repo/fastapi-app:TAG
