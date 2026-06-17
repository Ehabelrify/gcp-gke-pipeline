# ── gke.tf ────────────────────────────────────────────────────────────────────
# Provisions the GKE cluster and its node pool.
# Split into two resources (cluster + node pool) because GKE creates a "default"
# node pool automatically — we immediately delete it and manage our own so we
# have full control over machine type, SA, and auto-upgrade settings.

resource "google_container_cluster" "primary" {
  name = var.cluster_name

  # "location" set to a zone (not a region) = zonal cluster.
  # A zonal cluster has one control plane in one zone — cheaper than a regional
  # cluster (3 control planes across 3 zones) and fine for a portfolio project.
  location = var.zone

  # Tell GKE to delete the auto-created default node pool right after the
  # cluster is created. We define our own pool below with better settings.
  remove_default_node_pool = true
  initial_node_count       = 1 # required by GKE even though we delete it

  # Attach the cluster to our custom VPC and subnet
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # VPC-native networking (alias IP mode) — pods get IPs from the secondary
  # range we defined in network.tf instead of using node-level routes.
  # This is required for Workload Identity and private clusters.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"     # matches secondary_ip_range name in network.tf
    services_secondary_range_name = "services" # matches secondary_ip_range name in network.tf
  }

  # Workload Identity lets Kubernetes service accounts act as GCP service
  # accounts without mounting JSON keys into pods. Much more secure than
  # key files — the identity token is short-lived and rotated automatically.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# Our managed node pool — the actual VMs that run our workloads
resource "google_container_node_pool" "primary_nodes" {
  name     = "primary-node-pool"
  location = var.zone                               # must match the cluster's location
  cluster  = google_container_cluster.primary.name  # attach to our cluster
  node_count = var.node_count                       # 2 nodes by default (see variables.tf)

  node_config {
    # e2-small: 0.5 vCPU (burstable), 2 GB RAM — cheapest viable GKE node type.
    # GKE system pods consume ~500 MB per node; across 2 nodes we have ~3 GB
    # for actual workloads. We set resource limits in Phase 6 to stay within this.
    machine_type = var.machine_type

    # Reduce boot disk from the default 100 GB to 30 GB.
    # Our node images + container pulls fit easily within 30 GB.
    # Savings: ~$2.80/month per node vs the default.
    disk_size_gb = var.disk_size_gb

    # Assign our least-privilege service account (defined in iam.tf) to the nodes
    # This replaces the overly-broad Compute Engine default SA
    service_account = google_service_account.gke_sa.email

    # "cloud-platform" scope lets the node's SA use GCP APIs.
    # The SA's IAM roles (in iam.tf) are what actually control access —
    # the scope just unlocks the gate, IAM decides what's behind it.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Tell the node metadata server to expose GKE Workload Identity tokens
    # instead of the underlying node SA credentials — required for WI to work
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true  # GKE automatically replaces unhealthy nodes
    auto_upgrade = true  # GKE keeps nodes on a supported k8s version automatically
  }
}
