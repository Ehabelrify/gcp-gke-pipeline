# ── outputs.tf ────────────────────────────────────────────────────────────────
# Outputs print useful values to the terminal after `terraform apply` completes.
# They can also be read by other Terraform modules or CI/CD scripts.

output "cluster_name" {
  description = "Name of the GKE cluster — used in gcloud/kubectl commands"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The HTTPS endpoint of the GKE API server"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true # prevents this from printing in plain-text CI logs
}

output "region" {
  description = "GCP region where supporting resources live"
  value       = var.region
}

output "zone" {
  description = "GCP zone where the GKE cluster lives"
  value       = var.zone
}

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "gke_service_account_email" {
  description = "Email of the least-privilege SA attached to GKE nodes"
  value       = google_service_account.gke_sa.email
}

output "artifact_registry_url" {
  description = "Base URL for the Artifact Registry repo — prefix all image tags with this"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.repository_id}"
}

# After apply, connect kubectl to the cluster with:
# gcloud container clusters get-credentials <cluster_name> --zone <zone> --project <project_id>
#
# To push an image:
# gcloud auth configure-docker us-central1-docker.pkg.dev
# docker build -t us-central1-docker.pkg.dev/gcp-gke-pipeline-ehab/app-repo/fastapi-app:latest .
# docker push us-central1-docker.pkg.dev/gcp-gke-pipeline-ehab/app-repo/fastapi-app:latest
