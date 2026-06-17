# ── main.tf ───────────────────────────────────────────────────────────────────
# Entry point for Terraform. Declares which providers are needed and configures
# the Google provider with our project and region.

terraform {
  # Enforce a minimum Terraform CLI version to avoid syntax surprises
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google" # official Google provider from the Terraform registry
      version = "~> 5.0"          # "~> 5.0" means any 5.x release — allows patch upgrades
    }
  }
}

# The Google provider authenticates via Application Default Credentials (ADC).
# ADC is set up by running: gcloud auth application-default login
# Terraform reads ~/.config/gcloud/application_default_credentials.json automatically.
provider "google" {
  project = var.project_id # all resources default to this project unless overridden
  region  = var.region     # all resources default to this region unless overridden
}
