# ── network.tf ────────────────────────────────────────────────────────────────
# Defines the VPC and subnet that the GKE cluster will live in.
# Using a custom VPC (rather than the default one) is best practice — it gives
# us full control over IP ranges and avoids sharing a network with other GCP services.

# The VPC itself — just a named network container, no IPs at this level
resource "google_compute_network" "vpc" {
  name = "gke-vpc"

  # "false" = custom-mode VPC — we define subnets ourselves per region.
  # The alternative (auto_create_subnetworks = true) creates one subnet per
  # GCP region automatically, which we don't want — too broad and uncontrolled.
  auto_create_subnetworks = false
}

# The subnet where GKE nodes will run
resource "google_compute_subnetwork" "subnet" {
  name    = "gke-subnet"
  region  = var.region                    # must match the region in variables.tf
  network = google_compute_network.vpc.id # attach this subnet to our VPC

  # Primary range for nodes (the physical VMs).
  # /18 gives 16,382 usable IP addresses — far more than we need, but
  # this is a private range (10.x) so there's no cost to reserving it.
  ip_cidr_range = "10.0.0.0/18"

  # GKE VPC-native mode requires two secondary IP ranges:
  # one for Pods, one for Services. Without these, GKE falls back to
  # routes-based networking which doesn't scale and lacks some features.

  secondary_ip_range {
    range_name    = "pods"        # GKE references this name in the cluster config
    ip_cidr_range = "10.48.0.0/14" # ~260,000 IPs — pods scale fast so we give room
  }

  secondary_ip_range {
    range_name    = "services"      # GKE references this name in the cluster config
    ip_cidr_range = "10.52.0.0/20" # 4,094 IPs — plenty for ClusterIP services
  }
}
