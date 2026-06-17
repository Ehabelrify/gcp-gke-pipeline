# Build Journal

Chronological record of what was built, in what order, and why each decision was made.
This is a working log — not a setup guide. For reproducible setup instructions see the [README](../README.md).

---

## Phase 0 — Local Tooling & GCP Project Setup

**Goal:** All tools installed and authenticated before writing any code.

**Tools installed:**
- gcloud CLI (Google Cloud SDK)
- Terraform >= 1.5
- Helm
- kubectl (via `gcloud components install kubectl`)
- Docker Desktop (already present)

**GCP setup:**
```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default set-quota-project YOUR_PROJECT_ID

gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable artifactregistry.googleapis.com
```

**Decision — why enable APIs upfront:**
GCP APIs are disabled by default on new projects. Enabling them explicitly via CLI (rather than letting Terraform do it) gives a clean error surface — if an API fails to enable, you know before any infrastructure is provisioned.

---

## Phase 1 — Terraform: VPC + GKE Cluster

**Goal:** A working GKE cluster provisioned entirely by Terraform — no manual clicks in the GCP Console.

**Files written:**
- `terraform/main.tf` — Google provider, ADC authentication
- `terraform/variables.tf` — project ID, region, zone, machine type, disk size
- `terraform/network.tf` — custom VPC + subnet with pod/service secondary IP ranges
- `terraform/gke.tf` — zonal GKE cluster + managed node pool
- `terraform/iam.tf` — dedicated least-privilege service account for GKE nodes
- `terraform/outputs.tf` — cluster name, endpoint, SA email

**Commands run:**
```bash
cd terraform
terraform init     # downloads Google provider plugin (v5.45.2)
terraform plan     # previewed 9 resources: 1 VPC, 1 subnet, 1 SA, 4 IAM bindings, 1 cluster, 1 node pool
terraform apply    # provisioned in ~8 minutes
```

**Connect kubectl:**
```bash
gcloud container clusters get-credentials gke-pipeline-cluster \
  --zone us-central1-a --project YOUR_PROJECT_ID
kubectl get nodes  # confirmed 2 nodes Ready
```

**Key decisions:**
- **Zonal cluster** — single control plane, free. Regional would cost ~$72/month in management fees alone.
- **Custom VPC over default** — the default VPC is shared across all GCP services; a custom VPC gives network isolation and full IP range control.
- **VPC-native (alias IP) networking** — required for Workload Identity at the pod level; also avoids the 250-route limit of routes-based networking.
- **Two service accounts** — `gke-node-sa` for nodes (4 roles only), `github-actions-sa` for CI/CD (added in Phase 4). Never used the Compute Engine default SA.
- **e2-small initially, later upgraded to e2-medium** — started small to minimise cost, discovered in Phase 6 that e2-small couldn't fit the full monitoring stack alongside GKE system DaemonSet overhead.

**Result:** `terraform apply` — 9 resources, 0 errors. Both nodes `Ready`.

---

## Phase 2 — FastAPI App + Docker + Artifact Registry

**Goal:** A containerised application image pushed to a private registry in GCP.

**Files written:**
- `app/main.py` — FastAPI with 4 endpoints: `/`, `/health`, `/items`, `/secret`
- `app/requirements.txt` — `fastapi`, `uvicorn[standard]`, `hvac` (Vault client added in Phase 5)
- `Dockerfile` — `python:3.12-slim` base, layer-cache-optimised
- `terraform/artifact_registry.tf` — Artifact Registry Docker repository

**Commands run:**
```bash
# Provision the registry
cd terraform && terraform apply   # 1 new resource: google_artifact_registry_repository

# Authenticate Docker with Artifact Registry
gcloud auth configure-docker REGION-docker.pkg.dev

# Build and push
docker build -t REGION-docker.pkg.dev/PROJECT_ID/app-repo/fastapi-app:latest .
docker push REGION-docker.pkg.dev/PROJECT_ID/app-repo/fastapi-app:latest
```

**Key decisions:**
- **FastAPI over Flask** — auto-generates Swagger UI at `/docs`, async-native, typed request/response models.
- **python:3.12-slim** — removes dev tools and docs from the base image; ~60 MB vs ~900 MB for the full Python image.
- **Copy requirements before source** — Docker caches each layer independently; installing dependencies before copying source means a code-only change reuses the pip cache layer, making CI builds faster.

**Result:** Image visible in GCP Console under Artifact Registry.

---

## Phase 3 — Kubernetes Manifests + Deploy to GKE

**Goal:** Application running on GKE and publicly accessible via a load balancer.

**Files written:**
- `k8s/deployment.yaml` — 2 replicas, resource limits, liveness + readiness probes
- `k8s/service.yaml` — LoadBalancer Service, port 80 → container port 8000

**Commands run:**
```bash
kubectl apply -f k8s/
kubectl get pods              # confirmed 2 pods Running
kubectl get svc fastapi-app-svc   # waited for EXTERNAL-IP
curl http://EXTERNAL_IP/health    # {"status": "healthy"}
```

**Key decisions:**
- **2 replicas** — app survives a single pod failure; Kubernetes reschedules on the remaining node.
- **Liveness vs readiness probes** — liveness restarts a broken pod; readiness removes it from load balancer rotation without killing it. Both probe `/health`. A pod that is live but not ready (e.g. still warming up) won't receive traffic but also won't be force-restarted.
- **LoadBalancer Service** — provisions a GCP external HTTP load balancer automatically. Simpler than Ingress for a single-service demo.
- **Resource limits** — without limits, a memory leak in one pod could starve the entire node. Limits enforce isolation between workloads.

**Result:** App live and responding at public IP.

---

## Phase 4 — GitHub Actions CI/CD

**Goal:** Every push to `master` automatically builds, pushes, and deploys without manual steps.

**Files written:**
- `terraform/cicd.tf` — Workload Identity Federation pool, provider, CI/CD service account, WIF binding
- `.github/workflows/deploy.yml` — 8-step pipeline

**Commands run (Terraform):**
```bash
cd terraform
terraform apply   # 5 new resources: WIF pool, WIF provider, SA, 2 IAM bindings

# Get values for GitHub Secrets
terraform output workload_identity_provider
terraform output cicd_service_account_email
```

**GitHub Secrets added:**
- `GCP_WORKLOAD_IDENTITY_PROVIDER` — WIF provider resource name
- `GCP_SERVICE_ACCOUNT` — CI/CD service account email

**Key decisions:**
- **Workload Identity Federation over JSON keys** — WIF issues short-lived tokens per job; JSON keys are long-lived credentials that must be rotated and can be leaked. WIF tokens expire when the job ends and cannot be used outside the pipeline.
- **`attribute_condition` on the WIF provider** — scopes the trust to a specific GitHub repository. Without this, any GitHub Actions workflow in any public repo could request a GCP token.
- **`sed` + `kubectl apply` instead of `kubectl set image`** — `set image` only updates the image field. All other manifest changes (strategy, resource limits, probes) are ignored. `apply` sends the full manifest diff on every run.
- **Tagging with git SHA** — pinned image tags make rollbacks deterministic (`kubectl rollout undo` goes back to the exact image that last ran successfully).

**Result:** Pipeline green end-to-end. Verified by checking Artifact Registry for new image and confirming pods updated.

---

## Phase 5 — HashiCorp Vault via Helm

**Goal:** Secrets stored in Vault and read by the application at runtime — not hardcoded in manifests or environment files.

**Files written:**
- `k8s/vault/values.yaml` — Helm values for Vault in dev mode
- Updated `app/main.py` — `/secret` endpoint reads from Vault via `hvac`
- Updated `app/requirements.txt` — added `hvac==2.3.0`
- Updated `k8s/deployment.yaml` — added `VAULT_ADDR` and `VAULT_TOKEN` env vars

**Commands run:**
```bash
# Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault -f k8s/vault/values.yaml -n vault --create-namespace

# Wait for pod
kubectl get pods -n vault -w

# Write a secret
kubectl exec -n vault vault-0 -- vault kv put secret/app db_password=supersecret

# Verify
kubectl exec -n vault vault-0 -- vault kv get secret/app
```

**Push updated app through CI/CD:**
```bash
git add app/ k8s/
git commit -m "feat: deploy HashiCorp Vault and wire app to read secrets"
git push origin master
# GitHub Actions built new image with hvac, deployed to GKE
```

**Verified:**
```bash
curl http://EXTERNAL_IP/secret
# {"source": "vault", "db_password": "supersecret"}
```

**Key decisions:**
- **Dev mode** — no storage backend, no unseal ceremony, auto-starts. Appropriate for demonstrating the secret injection pattern without operating Vault as production infrastructure.
- **`hvac` Python client over direct HTTP** — cleaner API, handles KV v2 response structure automatically.
- **Internal DNS resolution** — `vault.vault.svc.cluster.local` resolves via Kubernetes DNS without exposing Vault outside the cluster. The pattern is `SERVICE.NAMESPACE.svc.cluster.local`.
- **Env vars for Vault address + token** — configurable at deploy time without rebuilding the image. In production, Vault Agent would handle token renewal and injection rather than a static env var.

**Result:** `/secret` returns live data from Vault.

---

## Phase 6 — Observability

**Goal:** Cluster and application metrics visible in Grafana; GCP-level monitoring via Cloud Monitoring.

**Files written:**
- `k8s/monitoring/values.yaml` — Helm values for kube-prometheus-stack (resource-tuned for the cluster)
- `terraform/monitoring.tf` — GCP uptime check + log-based metric for 5xx errors

**Commands run:**
```bash
# Install Prometheus + Grafana stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f k8s/monitoring/values.yaml -n monitoring --create-namespace

# Apply GCP monitoring resources
cd terraform && terraform apply

# Get load balancer IP for uptime check
kubectl get svc fastapi-app-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Access Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# http://localhost:3000 — admin / admin
```

**Components installed:**
| Component | Purpose |
|---|---|
| Prometheus | Metric collection (scrapes every 15s) |
| Grafana | Dashboards and visualisation |
| AlertManager | Alert routing |
| kube-state-metrics | Kubernetes object state metrics |
| node-exporter (×2) | Host-level node metrics |

**Key decisions:**
- **kube-prometheus-stack over standalone Prometheus** — the community chart bundles pre-built dashboards for Kubernetes, pre-configured scrape targets, and all supporting components in one install.
- **3-day metric retention** — default is 10 days; 3 days is sufficient for a demo and saves disk space on the 30 GB boot disks.
- **Explicit sidecar resource limits** — the chart deploys two `k8s-sidecar` containers alongside Grafana for dynamic dashboard/datasource loading from ConfigMaps. Their resource requests are unbounded by default, which blocked scheduling on a loaded cluster. Explicitly capping them was necessary.
- **GCP uptime check** — provides external validation that the app is reachable from outside the cluster, independent of cluster health. If the cluster is down, the uptime check still fires.

**Result:** All monitoring pods `Running`. Grafana accessible at `localhost:3000`. GCP uptime check active in Cloud Monitoring console.

---

## Phase 7 — Documentation

**Goal:** Standalone, recruiter-facing README and supporting documentation.

**Files written:**
- `README.md` — full rewrite with Mermaid architecture diagram, stack table, setup guide, design decisions, cost estimate
- `docs/application.md` — app endpoints, environment variables, Kubernetes config
- `docs/troubleshooting.md` — 11 issues with root causes, debug commands, and fixes
- `docs/build-journal.md` — this file
- `docs/screenshots/` — visual evidence of the running system
