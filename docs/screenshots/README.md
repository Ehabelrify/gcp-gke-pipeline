# Screenshots

Visual evidence of the running system. Add screenshots here as PNG or JPG files.

---

## What to capture

### 1. FastAPI Swagger UI — `swagger-ui.png`
Open `http://EXTERNAL_IP/docs` in a browser.
Shows all 5 endpoints listed with their HTTP methods and descriptions.

**How to get the IP:**
```bash
kubectl get svc fastapi-app-svc
```

---

### 2. `/health` endpoint — `health-endpoint.png`
Open `http://EXTERNAL_IP/health` in a browser or run:
```bash
curl http://EXTERNAL_IP/health
```
Expected output: `{"status":"healthy"}`

---

### 3. `/secret` endpoint — `vault-secret.png`
Open `http://EXTERNAL_IP/secret` in a browser or run:
```bash
curl http://EXTERNAL_IP/secret
```
Expected output: `{"source":"vault","db_password":"supersecret"}`

This proves the app is reading secrets live from HashiCorp Vault at runtime.

---

### 4. Grafana dashboard — `grafana-dashboard.png`
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```
Open `http://localhost:3000`, log in with `admin / admin`.
Navigate to **Dashboards → Kubernetes / Compute Resources / Cluster**.
Shows CPU usage, memory usage, and network traffic across the cluster.

---

### 5. Grafana — pod status view — `grafana-pods.png`
From Grafana dashboards, open **Kubernetes / Compute Resources / Namespace (Pods)**.
Set namespace to `default`.
Shows the FastAPI pods and their resource consumption in real time.

---

### 6. GitHub Actions pipeline — `github-actions.png`
Open the repository on GitHub → **Actions** tab.
Click a successful run to show all 8 steps passing:
- Checkout
- Authenticate to GCP
- Setup gcloud / install plugin
- Configure Docker
- Build image
- Push image
- Get GKE credentials
- Deploy + rollout status

---

### 7. GCP Console — GKE Workloads — `gcp-gke-workloads.png`
In the GCP Console → **Kubernetes Engine → Workloads**.
Shows: `fastapi-app` deployment (2/2 pods), `vault` StatefulSet, `kube-prometheus-stack` components.

---

### 8. GCP Console — Artifact Registry — `artifact-registry.png`
GCP Console → **Artifact Registry → Repositories → app-repo**.
Shows the `fastapi-app` image with multiple tags (one per git SHA from CI/CD runs + `latest`).

---

### 9. GCP Console — Cloud Monitoring uptime check — `uptime-check.png`
GCP Console → **Monitoring → Uptime checks**.
Shows the `fastapi-app-health` check with green status, response time graph, and 100% uptime.

---

## Naming convention

Use the filenames listed above so references in the docs remain consistent:

```
docs/screenshots/
├── swagger-ui.png
├── health-endpoint.png
├── vault-secret.png
├── grafana-dashboard.png
├── grafana-pods.png
├── github-actions.png
├── gcp-gke-workloads.png
├── artifact-registry.png
└── uptime-check.png
```
