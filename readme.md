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

**Issues encountered:**
- **`Permission denied` on gcloud credential file** — gcloud was first run as Administrator, which created `adc.json` owned by the Admin account. Regular user sessions couldn't write to it, breaking all gcloud commands.
  - Fix: `takeown /f ... /r` to take ownership of the gcloud config directory, then `icacls` to grant the regular user full access, then re-authenticated with `gcloud auth login`.
- **`gke-gcloud-auth-plugin` missing** — kubectl v1.26+ requires this separate plugin to authenticate with GKE; it is not bundled with the gcloud CLI by default.
  - Fix: `gcloud components install gke-gcloud-auth-plugin` and set `USE_GKE_GCLOUD_AUTH_PLUGIN=True` in the shell session.

---

### ✅ Phase 1 — Terraform: VPC + GKE cluster
- Custom VPC (`gke-vpc`) with a dedicated subnet and secondary IP ranges for pods and services (VPC-native networking)
- GKE zonal cluster (`gke-pipeline-cluster`, `us-central1-a`) with 2x `e2-small` nodes running Kubernetes v1.35.5
- Dedicated least-privilege service account (`gke-node-sa`) with only 4 IAM roles: Artifact Registry reader, log writer, metric writer, monitoring viewer
- Workload Identity enabled on the cluster and node pool (no JSON keys needed for pod-level GCP auth)
- `terraform apply` — 9 resources provisioned, 0 errors
- kubectl connected, both nodes `Ready`

**Issues encountered:** None.

---

### ✅ Phase 2 — FastAPI app + Docker + Artifact Registry
- FastAPI app with 4 endpoints: `/` (service info), `/health` (k8s probe target), `/items` (sample data), `/secret` (Vault placeholder)
- Dockerfile using `python:3.12-slim` — dependencies copied before source code to maximize Docker layer caching
- Artifact Registry repository (`app-repo`) provisioned via Terraform
- Image built and pushed: `us-central1-docker.pkg.dev/gcp-gke-pipeline-ehab/app-repo/fastapi-app:latest`

**Issues encountered:** None.

---

### ✅ Phase 3 — Kubernetes manifests + deploy to GKE
- `Deployment` with 2 replicas, resource requests/limits sized for e2-small nodes (50m CPU / 128Mi RAM per pod)
- Liveness probe on `/health` — restarts the pod if the app deadlocks
- Readiness probe on `/health` — removes the pod from load balancer rotation until it's ready
- `Service` of type `LoadBalancer` — GCP external load balancer on port 80 → container port 8000
- App live and responding: `GET /health → {"status": "healthy"}`

**Issues encountered:** None.

---

### ✅ Phase 4 — GitHub Actions CI/CD
- Workload Identity Federation (WIF) configured — GitHub Actions authenticates to GCP via short-lived OIDC tokens, no JSON keys stored in GitHub Secrets
- Dedicated CI/CD service account (`github-actions-sa`) with Artifact Registry writer + GKE developer roles
- Pipeline: checkout → WIF auth → build image (tagged with git SHA) → push to Artifact Registry → rolling deploy to GKE

**Issues encountered:**
- **Rolling update failed with `Insufficient cpu`** — Kubernetes default rolling update creates a new pod before terminating an old one (`maxSurge: 1`). With 2 replicas this temporarily requires 3 pods, but e2-small nodes didn't have enough free CPU to schedule the 3rd pod.
  - Fix: Set `maxSurge: 0, maxUnavailable: 1` in the Deployment strategy so old pods are terminated first. Also reduced CPU requests from 100m to 50m (FastAPI is lightweight and the headroom is needed for Vault and Prometheus in later phases).
- **Strategy change not applied via `kubectl set image`** — the pipeline was using `kubectl set image` to update only the image tag, which left all other manifest changes (including the `maxSurge: 0` fix) unapplied on the live cluster.
  - Fix: Replaced `kubectl set image` with `sed` to substitute the image tag in `deployment.yaml` followed by `kubectl apply -f k8s/` — this ensures every manifest change is applied on every deploy, not just the image tag.
- **Node.js 20 deprecation warning in GitHub Actions** — actions (`checkout@v4`, `google-github-actions/auth@v2`, etc.) internally target Node.js 20, which GitHub has deprecated on runners. GitHub automatically forces them to run on Node.js 24. Non-breaking warning only — no action required.

---

### ✅ Phase 5 — HashiCorp Vault via Helm
- Vault deployed in dev mode via Helm into a dedicated `vault` namespace (auto-unsealed, in-memory storage — correct scope for a portfolio project; production would use Raft storage + GCP KMS auto-unseal)
- Secret written: `vault kv put secret/app db_password=supersecret`
- FastAPI `/secret` endpoint updated to read `db_password` from Vault KV v2 engine via the `hvac` Python client
- `VAULT_ADDR` and `VAULT_TOKEN` injected as env vars in the Deployment manifest; app resolves Vault via Kubernetes internal DNS (`vault.vault.svc.cluster.local`)

**Issues encountered:** None.

---

### ✅ Phase 6 — Observability (Prometheus + Grafana)
- kube-prometheus-stack installed via Helm in `monitoring` namespace (Prometheus + Grafana + AlertManager + kube-state-metrics + node-exporter)
- All resource requests tuned down for e2-small nodes (Prometheus: 256Mi, Grafana: 64Mi, AlertManager: 32Mi)
- GCP uptime check provisioned via Terraform — pings `/health` every 60s from GCP infrastructure
- Log-based metric for 5xx errors configured in Cloud Logging

**Issues encountered:**
- **`helm install` failed with "cannot reuse a name that is still in use"** — a previous partial install attempt left the Helm release registered. Running `helm install` again with the same release name fails even if the release is broken.
  - Fix: use `helm upgrade --install` instead — idempotent, installs if missing and upgrades if already present.
- **Terraform `google_logging_metric` failed with "Label descriptors must have corresponding label extractors"** — defined a `labels` block inside `metric_descriptor` without a matching `label_extractors` block that maps log fields to those labels. GCP requires both to be present together.
  - Fix: removed the `labels` block entirely — a simple count of 5xx errors without label breakdown is sufficient and avoids the complexity.
- **Prometheus pod stuck `Pending` — `Insufficient cpu, Insufficient memory`** — kube-prometheus-stack's default resource requests are sized for production clusters. Combined with GKE system DaemonSets (logging agent, kube-proxy, etc.) and existing workloads (Vault, FastAPI), both e2-small nodes were fully exhausted before Prometheus could schedule.
  - Fix: reduced Prometheus requests to 50m CPU / 128Mi memory. Also explicitly set resource requests on the two Grafana sidecar containers (`k8s-sidecar`) which the chart leaves unbounded by default, causing them to consume headroom invisibly.
- **Grafana liveness probe killing the container on startup** — the default liveness probe fires after 30s, but Grafana takes longer to boot on a resource-constrained node. The probe declared the container unhealthy and killed it repeatedly (`CrashLoopBackOff`).
  - Fix: increased `livenessProbe.initialDelaySeconds` to 60s and `failureThreshold` to 6 to give Grafana enough time to start under load.
- **Grafana OOMKilled repeatedly even after liveness probe fix** — Grafana 13 requires more than 128Mi to boot. The pod would start, briefly reach 2/3 containers, then get killed by the kernel for exceeding the memory limit before the liveness probe even fired.
  - Fix: increased Grafana memory request to 128Mi and limit to 256Mi. Also increased sidecar container limits from 64Mi to 128Mi.
- **Rolling update deadlock after force-deleting OOMKilled pod** — deleting the old Grafana pod caused its ReplicaSet controller to immediately create a replacement, while the new pod was still at 2/3. Both pods competed for the same resources, stalling the rollout. 
  - Fix: waited for the new pod to reach 3/3 Ready, at which point the rolling update automatically terminated the old ReplicaSet's replacement pod.
- **e2-small nodes fully exhausted — upgraded to e2-medium** — even with aggressively reduced resource requests, the combination of GKE system DaemonSets (fluentbit logging agent, kube-proxy, metadata server, pdcsi-node) consuming ~500 MB and significant CPU per node, plus the full workload stack (FastAPI × 2, Vault, Prometheus, Grafana, AlertManager, node-exporter × 2, kube-state-metrics), left both nodes with `Insufficient cpu` and `Insufficient memory` for pending pods. GKE system overhead on e2-small is simply too high for a multi-component stack.
  - Fix: upgraded node pool from `e2-small` (2 GB RAM) to `e2-medium` (4 GB RAM) via Terraform. GKE performed a rolling node replacement with zero downtime. All monitoring pods scheduled and reached `Running` immediately after.
### Phase 7 — Final README + architecture diagram

## Setup

_Full setup instructions will be written in Phase 7 once the project is complete._

## Cost Note

The GKE cluster (2x e2-small nodes) runs against GCP free trial credit (~$24/month for nodes + ~$2.40/month for disks). The LoadBalancer Service adds ~$18/month while running. Run `terraform destroy` after testing to avoid unnecessary charges.