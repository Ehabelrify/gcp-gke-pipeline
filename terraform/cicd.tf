# ── cicd.tf ───────────────────────────────────────────────────────────────────
# Sets up Workload Identity Federation (WIF) so GitHub Actions can authenticate
# to GCP without storing a long-lived JSON service account key in GitHub Secrets.
#
# How WIF works:
#  1. GitHub Actions generates a short-lived OIDC token signed by GitHub.
#  2. GCP verifies that token against GitHub's public OIDC endpoint.
#  3. If valid, GCP issues a short-lived GCP access token for our CI/CD SA.
#  4. The workflow uses that token for the rest of the job — it expires when done.
#
# Nothing sensitive is ever stored anywhere. Zero secret rotation needed.

# ── Workload Identity Pool ────────────────────────────────────────────────────
# A pool is a container that groups external identity providers.
# Think of it as "a place where we trust identities from outside GCP".
resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Trusts OIDC tokens issued by GitHub Actions"
}

# ── Workload Identity Provider ────────────────────────────────────────────────
# A provider maps an external OIDC issuer (GitHub) to our pool.
# It defines WHICH GitHub tokens we accept and HOW to map their claims
# to GCP attributes we can use in IAM conditions.
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions OIDC Provider"

  # Map claims from the GitHub JWT to GCP attributes.
  # "assertion" refers to the incoming GitHub token's payload.
  attribute_mapping = {
    "google.subject"       = "assertion.sub"        # stable unique ID for the workflow
    "attribute.actor"      = "assertion.actor"       # GitHub username who triggered the run
    "attribute.repository" = "assertion.repository"  # "owner/repo" — we use this for the condition below
  }

  # Security gate: only accept tokens from OUR specific repository.
  # Without this, any GitHub Actions workflow in any repo could request a token.
  attribute_condition = "assertion.repository == 'Ehabelrify/gcp-gke-pipeline'"

  oidc {
    # GitHub's OIDC endpoint — GCP fetches the public keys from here to verify tokens
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ── CI/CD Service Account ─────────────────────────────────────────────────────
# A dedicated SA for GitHub Actions — separate from the GKE node SA.
# Principle of least privilege: CI/CD only gets push + deploy, nothing else.
resource "google_service_account" "cicd_sa" {
  project      = var.project_id
  account_id   = "github-actions-sa"
  display_name = "GitHub Actions CI/CD Service Account"
  description  = "Used by GitHub Actions via WIF to push images and deploy to GKE"
}

# Grant: push Docker images to Artifact Registry
resource "google_project_iam_member" "cicd_sa_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cicd_sa.email}"
}

# Grant: deploy workloads to GKE (kubectl set image, rollout, apply)
resource "google_project_iam_member" "cicd_sa_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.cicd_sa.email}"
}

# ── WIF Binding ───────────────────────────────────────────────────────────────
# This is the binding that makes WIF actually work.
# It says: "any GitHub Actions workflow from our repo is allowed to impersonate
# the cicd_sa service account".
# principalSet://... matches ALL tokens from our repo (any branch, any trigger).
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = google_service_account.cicd_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/Ehabelrify/gcp-gke-pipeline"
}
