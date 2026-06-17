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

# After apply, connect kubectl to the cluster with:
# gcloud container clusters get-credentials <cluster_name> --zone <zone> --project <project_id>
