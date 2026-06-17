# GCP GKE Pipeline

An end-to-end DevOps pipeline on Google Cloud Platform. Provisions a production-style GKE cluster with Terraform, deploys a containerized application through a GitHub Actions CI/CD pipeline, manages secrets with HashiCorp Vault, and exposes metrics via Prometheus and Grafana.

> **Status:** In progress — actively building phase by phase.

## Planned Stack

| Layer | Technology |
|-------|-----------|
| Infrastructure | Terraform, GCP (GKE, VPC, Artifact Registry, IAM) |
| Application | Python / FastAPI |
| Containers | Docker, Google Artifact Registry |
| Orchestration | Kubernetes (GKE) |
| CI/CD | GitHub Actions |
| Secrets | HashiCorp Vault (Helm) |
| Observability | Cloud Monitoring, Prometheus, Grafana (Helm) |

## Architecture

_Diagram to be added once all phases are complete._

## Phases

### ✅ Phase 0 — Local tooling & GCP project setup
- Installed gcloud CLI, Terraform, Helm, kubectl on Windows 11
- Authenticated with `gcloud auth login` and `gcloud auth application-default login`
- Created GCP project `gcp-gke-pipeline-ehab`
- Enabled APIs: Compute Engine, GKE, Artifact Registry
- Configured Application Default Credentials for Terraform

### ✅ Phase 1 — Terraform: VPC + GKE cluster
- Custom VPC (`gke-vpc`) with a dedicated subnet and secondary IP ranges for pods and services (VPC-native networking)
- GKE zonal cluster (`gke-pipeline-cluster`, `us-central1-a`) with 2x `e2-small` nodes running Kubernetes v1.35.5
- Dedicated least-privilege service account (`gke-node-sa`) with only 4 IAM roles: Artifact Registry reader, log writer, metric writer, monitoring viewer
- Workload Identity enabled on the cluster and node pool (no JSON keys needed for pod-level GCP auth)
- `terraform apply` — 9 resources provisioned, 0 errors
- kubectl connected, both nodes `Ready`

### ✅ Phase 2 — FastAPI app + Docker + Artifact Registry
- FastAPI app with 4 endpoints: `/` (service info), `/health` (k8s probe target), `/items` (sample data), `/secret` (Vault placeholder)
- Dockerfile using `python:3.12-slim` — dependencies copied before source code to maximize Docker layer caching
- Artifact Registry repository (`app-repo`) provisioned via Terraform
- Image built and pushed: `us-central1-docker.pkg.dev/gcp-gke-pipeline-ehab/app-repo/fastapi-app:latest`

### ✅ Phase 3 — Kubernetes manifests + deploy to GKE
- `Deployment` with 2 replicas, resource requests/limits sized for e2-small nodes (100m CPU / 128Mi RAM per pod)
- Liveness probe on `/health` — restarts the pod if the app deadlocks
- Readiness probe on `/health` — removes the pod from load balancer rotation until it's ready
- `Service` of type `LoadBalancer` — GCP external load balancer on port 80 → container port 8000
- App live and responding: `GET /health → {"status": "healthy"}`

### 🔧 Phase 4 — GitHub Actions CI/CD _(next)_
### Phase 3 — Kubernetes manifests + deploy to GKE
### Phase 4 — GitHub Actions CI/CD
### Phase 5 — HashiCorp Vault via Helm
### Phase 6 — Observability (Prometheus + Grafana)
### Phase 7 — Final README + architecture diagram

## Setup

_Full setup instructions will be written in Phase 7 once the project is complete._

## Cost Note

The GKE cluster (2x e2-medium nodes) runs against GCP free trial credit (~$25–40/month). Run `terraform destroy` after testing to avoid unnecessary charges.