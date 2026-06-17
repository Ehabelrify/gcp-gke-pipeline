# Application Documentation

## Overview

The application is a lightweight REST API built with **FastAPI** (Python 3.12). It runs as a containerised service inside the GKE cluster and demonstrates the full pipeline: CI/CD build, container registry, Kubernetes deployment, and live secret injection from HashiCorp Vault.

---

## Endpoints

### `GET /`
Returns basic service information.

**Example response:**
```json
{
  "service": "gcp-gke-pipeline",
  "status": "running",
  "description": "FastAPI app deployed on GKE via GitHub Actions CI/CD"
}
```

---

### `GET /health`
Health check endpoint. Used by Kubernetes liveness and readiness probes.

- **Liveness probe** — if this fails 3 consecutive times, Kubernetes restarts the pod
- **Readiness probe** — if this fails, the pod is removed from the load balancer until it recovers

**Example response:**
```json
{
  "status": "healthy"
}
```

---

### `GET /items`
Sample data endpoint demonstrating a standard API response.

**Example response:**
```json
{
  "items": [
    {"id": 1, "name": "item-alpha", "value": 100},
    {"id": 2, "name": "item-beta",  "value": 200},
    {"id": 3, "name": "item-gamma", "value": 300}
  ]
}
```

---

### `GET /secret`
Reads the `db_password` secret live from HashiCorp Vault's KV v2 engine at runtime.

The app connects to Vault using the address and token injected as environment variables by the Kubernetes Deployment manifest. The Vault service is resolved via Kubernetes internal DNS (`vault.vault.svc.cluster.local`).

**Example response (Vault reachable):**
```json
{
  "source": "vault",
  "db_password": "supersecret"
}
```

**Example response (Vault unreachable):**
```json
{
  "detail": "Could not reach Vault: ..."
}
```

---

### `GET /docs`
Auto-generated interactive API documentation provided by FastAPI (Swagger UI). Accessible in the browser — lists all endpoints, shows request/response schemas, and allows live requests.

---

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `VAULT_ADDR` | Address of the Vault server | `http://vault.vault.svc.cluster.local:8200` |
| `VAULT_TOKEN` | Token used to authenticate with Vault | `root` |

These are injected by the Kubernetes Deployment manifest. In a production setup, `VAULT_TOKEN` would be a dynamic, short-lived token provided by Vault Agent rather than a static root token.

---

## Container Image

The app is packaged as a Docker image using `python:3.12-slim` as the base.

**Build optimisation:** `requirements.txt` is copied and dependencies are installed before the application source code is copied. This means Docker can cache the dependency installation layer — a code-only change reuses the cached layer, making rebuilds significantly faster.

**Image location:** Google Artifact Registry  
**Image URL pattern:** `REGION-docker.pkg.dev/PROJECT_ID/app-repo/fastapi-app:TAG`

Each CI/CD pipeline run pushes two tags:
- `:GIT_SHA` — immutable, pinned to the exact commit that produced it (used for rollbacks)
- `:latest` — always points to the most recent successful build

---

## Kubernetes Configuration

The app runs as a `Deployment` with the following configuration:

| Setting | Value | Reason |
|---|---|---|
| Replicas | 2 | Survives a single pod failure |
| CPU request | 50m | FastAPI is lightweight at idle |
| CPU limit | 200m | Allows burst for request spikes |
| Memory request | 128Mi | Baseline Python + FastAPI footprint |
| Memory limit | 256Mi | Hard cap — OOMKill prevents node exhaustion |
| Rolling update | `maxSurge: 0, maxUnavailable: 1` | Avoids scheduling a 3rd pod during updates on a small cluster |
| Liveness probe | `GET /health` every 15s | Restarts deadlocked pods |
| Readiness probe | `GET /health` every 10s | Keeps unready pods out of load balancer rotation |

---

## Accessing the Application

**Via LoadBalancer (public):**
```bash
kubectl get svc fastapi-app-svc
# Use the EXTERNAL-IP shown in the output
curl http://EXTERNAL_IP/health
curl http://EXTERNAL_IP/secret
curl http://EXTERNAL_IP/docs   # open in browser for Swagger UI
```

**Via port-forward (local, no public IP needed):**
```bash
kubectl port-forward svc/fastapi-app-svc 8080:80
# Then visit http://localhost:8080
```

---

## Screenshots

See [`screenshots/`](screenshots/) for:
- Swagger UI (`/docs`) showing all endpoints
- `/secret` endpoint response showing live Vault integration
- `/health` response in browser
- GKE workloads view showing running pods
