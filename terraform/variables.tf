# ── variables.tf ──────────────────────────────────────────────────────────────
# Centralises all configurable values so nothing is hard-coded in resource files.
# Change these here and every resource that references them updates automatically.

variable "project_id" {
  description = "The GCP project ID that all resources will be created in."
  type        = string
  default     = "gcp-gke-pipeline-ehab"
}

variable "region" {
  description = "GCP region for the VPC subnet and supporting resources."
  type        = string
  default     = "us-central1" # cheapest region, lowest latency from US east
}

variable "zone" {
  description = "GCP zone for the GKE cluster. Zonal (single-zone) is cheaper than regional."
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name given to the GKE cluster."
  type        = string
  default     = "gke-pipeline-cluster"
}

variable "node_count" {
  description = "Number of nodes in the GKE node pool."
  type        = number
  default     = 2 # 2 nodes gives headroom for app + Vault + monitoring
}

variable "machine_type" {
  description = "GCE machine type for GKE worker nodes."
  type        = string
  # e2-medium: 1 vCPU (burstable), 4 GB RAM — ~$25/month per node.
  # Upgraded from e2-small after the full stack (FastAPI + Vault + Prometheus +
  # Grafana + AlertManager + node-exporter) exhausted both nodes' allocatable
  # CPU and memory. GKE system DaemonSets (fluentbit, kube-proxy, metadata server)
  # consume ~500 MB and significant CPU that wasn't accounted for at e2-small size.
  default = "e2-medium"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB per node. GKE minimum is 10 GB; 30 GB is safe for our images."
  type        = number
  # Default is 100 GB ($4/month per node). 30 GB cuts that to $1.20/month per node.
  default = 30
}
