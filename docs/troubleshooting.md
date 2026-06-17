# Troubleshooting Log

All issues encountered during the build of this project, in chronological order.
Each entry includes the symptom, root cause, debugging commands used, and the fix applied.

---

## Phase 0 — Local Tooling & GCP Setup

---

### Issue 1 — `Permission denied` on gcloud credential file

**Symptom**
```
ERROR: (gcloud.config.config-helper) Error saving Application Default Credentials:
Unable to create private file
[C:\Users\YOUR_USERNAME\AppData\Roaming\gcloud\legacy_credentials\YOUR_EMAIL\adc.json]:
[Errno 13] Permission denied
```
Every gcloud command failed, including `kubectl get nodes` which calls gcloud internally via `gke-gcloud-auth-plugin`.

**Root cause**
The gcloud CLI was first run as Administrator during installation. This created credential files under `%APPDATA%\gcloud\` owned by the Windows Administrator account. Subsequent runs as a regular user could not write to those files.

**Debugging commands**
```powershell
# Confirm the file exists but is unwritable
ls "$env:APPDATA\gcloud\legacy_credentials\YOUR_EMAIL\"

# Check who owns the file (run as Admin)
icacls "$env:APPDATA\gcloud\legacy_credentials\YOUR_EMAIL\adc.json"
```

**Fix**
Run PowerShell as Administrator:
```powershell
# Take ownership of all files under the gcloud config directory
takeown /f "$env:APPDATA\gcloud" /r /d y

# Grant the regular user full control (replace YOUR_USERNAME with your Windows username)
icacls "$env:APPDATA\gcloud" /grant "YOUR_USERNAME:(OI)(CI)F" /T

# Delete the locked file so gcloud recreates it with correct ownership
Remove-Item "$env:APPDATA\gcloud\legacy_credentials\YOUR_EMAIL\adc.json" -Force
```
Then re-authenticate in a regular PowerShell session:
```powershell
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

---

### Issue 2 — `gke-gcloud-auth-plugin` not found

**Symptom**
```
error: exec: executable gke-gcloud-auth-plugin.exe failed with exitcode 1
Unable to connect to the server: getting credentials: exec: executable
gke-gcloud-auth-plugin.exe failed with exit code 1
```

**Root cause**
kubectl v1.26+ requires a separate `gke-gcloud-auth-plugin` binary to authenticate with GKE clusters. It is not bundled with the gcloud CLI by default and must be installed as a separate component.

**Fix**
```powershell
gcloud components install gke-gcloud-auth-plugin

# Set the env var that tells kubectl to use the plugin (required in the same session)
$env:USE_GKE_GCLOUD_AUTH_PLUGIN = "True"

# Re-fetch credentials now that the plugin is present
gcloud container clusters get-credentials gke-pipeline-cluster `
  --zone us-central1-a --project YOUR_PROJECT_ID
```

---

## Phase 4 — GitHub Actions CI/CD

---

### Issue 3 — Rolling update failed: `Insufficient cpu`

**Symptom**
```
error: timed out waiting for the condition
0/2 nodes are available: 2 Insufficient cpu.
no new claims to deallocate, preemption: 0/2 nodes are available:
2 No preemption victims found for incoming pod.
```

**Root cause**
Kubernetes default rolling update strategy is `maxSurge: 1` — it creates one new pod before terminating an old one, temporarily requiring capacity for N+1 pods. With 2 replicas this means 3 pods during transition. Each pod requested 100m CPU, totalling 300m, which exceeded available capacity on the e2-small nodes after accounting for GKE system pod overhead.

**Debugging commands**
```bash
# Check pod status
kubectl get pods

# Describe the stuck pod to see scheduling events
kubectl describe pod <pending-pod-name>

# Check node resource allocation
kubectl describe nodes | grep -A 10 "Allocated resources"
```

**Fix**
Updated `k8s/deployment.yaml` to use `maxSurge: 0, maxUnavailable: 1` — this terminates one old pod first before creating the replacement, keeping total pod count at N during the update. Also reduced CPU request from 100m to 50m:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 0
    maxUnavailable: 1
```

---

### Issue 4 — Manifest strategy change not applied via `kubectl set image`

**Symptom**
The `maxSurge: 0` fix was applied to `deployment.yaml` locally but the pipeline continued using `kubectl set image`, which only updates the image tag on the live Deployment object — it does not re-apply other fields from the manifest file. The cluster still had `maxSurge: 1` from the initial apply.

**Root cause**
`kubectl set image deployment/fastapi-app fastapi-app=IMAGE:SHA` is a targeted patch — it changes one field. Any other changes in `deployment.yaml` (strategy, resource limits, probes) are ignored.

**Fix**
Changed the deploy step in `.github/workflows/deploy.yml` to use `sed` + `kubectl apply` instead:

```bash
# Substitute the image tag in the manifest file
sed -i "s|fastapi-app:latest|fastapi-app:${{ github.sha }}|g" k8s/deployment.yaml

# Apply the full manifest — picks up ALL changes including strategy
kubectl apply -f k8s/

# Wait for rollout
kubectl rollout status deployment/fastapi-app --timeout=300s
```

This ensures every field in the manifest is applied on every deploy, not just the image tag.

---

### Issue 5 — Node.js 20 deprecation warning in GitHub Actions

**Symptom**
```
Node.js 20 is deprecated. The following actions target Node.js 20 but are being
forced to run on Node.js 24: actions/checkout@v4, google-github-actions/auth@v2,
google-github-actions/get-gke-credentials@v2, google-github-actions/setup-gcloud@v2
```

**Root cause**
The GitHub Actions used internally target Node.js 20, which GitHub has deprecated on runners. GitHub automatically upgrades them to Node.js 24 at runtime.

**Impact**
None — warning only. The pipeline runs correctly. No action required.

---

## Phase 6 — Observability

---

### Issue 6 — `helm install` failed: "cannot reuse a name that is still in use"

**Symptom**
```
level=ERROR msg="release name check failed"
error="cannot reuse a name that is still in use"
Error: INSTALLATION FAILED: release name check failed
```

**Root cause**
A previous `helm install` attempt had partially succeeded, registering the release name in Helm's state. Running `helm install` again with the same name fails even if the release is in a broken state.

**Fix**
Use `helm upgrade --install` which is idempotent — installs if the release doesn't exist, upgrades if it does:
```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f k8s/monitoring/values.yaml \
  -n monitoring --create-namespace
```

---

### Issue 7 — Terraform `google_logging_metric` failed: label descriptor mismatch

**Symptom**
```
Error: Error creating Metric: googleapi: Error 400:
Label descriptors must have corresponding label extractors
```

**Root cause**
A `labels` block was defined inside `metric_descriptor` without a corresponding `label_extractors` block. GCP requires both to be present together — the label descriptor declares the label schema, and the extractor defines how to parse the label's value from log entries.

**Fix**
Removed the `labels` block entirely. A simple count of 5xx errors without label breakdown is sufficient and avoids the complexity of writing a log extractor regex:

```hcl
metric_descriptor {
  metric_kind = "DELTA"
  value_type  = "INT64"
  unit        = "1"
  # No labels — total count only
}
```

---

### Issue 8 — Prometheus pod stuck `Pending`: `Insufficient cpu, Insufficient memory`

**Symptom**
```
0/2 nodes are available: 2 Insufficient cpu, 2 Insufficient memory.
no new claims to deallocate
```

**Root cause**
kube-prometheus-stack's default resource requests are sized for production clusters. GKE system DaemonSets (fluentbit logging agent, kube-proxy, gke-metadata-server, pdcsi-node) consume approximately 500 MB and significant CPU per node — more than initially estimated. Combined with existing workloads (FastAPI × 2, Vault, Grafana), there was no room for Prometheus on either e2-small node.

**Debugging commands**
```bash
# Check pod status across namespaces
kubectl get pods -n monitoring

# See why the pod is Pending
kubectl describe pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring

# See actual resource allocation per node
kubectl describe nodes | grep -A 10 "Allocated resources"

# Check actual resource usage (not just requests)
kubectl top pods -n monitoring
kubectl top nodes
```

**Fix (step 1 — reduce requests)**
Updated `k8s/monitoring/values.yaml` to reduce Prometheus requests to 50m CPU / 128Mi memory, and explicitly set resource requests on the Grafana sidecar containers which the chart leaves unbounded by default:

```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: "50m"
        memory: "128Mi"

grafana:
  sidecar:
    resources:
      requests:
        cpu: "10m"
        memory: "32Mi"
      limits:
        cpu: "50m"
        memory: "128Mi"
```

**Fix (step 2 — upgrade node size)**
Even with minimized requests, e2-small nodes (2 GB RAM) could not fit the full stack after GKE system overhead. Upgraded node pool from `e2-small` to `e2-medium` (4 GB RAM) via Terraform:

```hcl
# terraform/variables.tf
variable "machine_type" {
  default = "e2-medium"
}
```

```bash
cd terraform && terraform apply
```

GKE performed a rolling node replacement with zero downtime — one node was drained and recreated at the new size while workloads ran on the other, then the process repeated.

---

### Issue 9 — Grafana OOMKilled repeatedly

**Symptom**
```
kube-prometheus-stack-grafana   1/3   OOMKilled   9 (8s ago)
```

**Root cause**
Grafana 13 requires more than 128Mi to boot. The memory limit was too low — the container would start, allocate memory during initialization, and be killed by the kernel OOM killer before it became ready.

**Fix**
Increased Grafana memory limit in `k8s/monitoring/values.yaml`:
```yaml
grafana:
  resources:
    requests:
      memory: "128Mi"
    limits:
      memory: "256Mi"   # was 128Mi
```

---

### Issue 10 — Grafana liveness probe killing container mid-startup

**Symptom**
```
Warning  Unhealthy  kubelet  Liveness probe failed:
Get "http://<pod-ip>:3000/api/health": dial tcp <pod-ip>:3000: connect: connection refused
Normal   Killing    kubelet  Container grafana failed liveness probe, will be restarted
```

**Root cause**
The default liveness probe fires after 30 seconds. On a loaded node, Grafana takes longer than 30s to complete startup — plugins load, database initializes, background services start. The probe declared the container dead and restarted it before it could finish booting, creating an infinite restart loop.

**Fix**
Increased liveness probe thresholds in `k8s/monitoring/values.yaml`:
```yaml
grafana:
  livenessProbe:
    initialDelaySeconds: 60   # was 30
    timeoutSeconds: 5
    periodSeconds: 10
    failureThreshold: 6       # was 3
  readinessProbe:
    initialDelaySeconds: 30
    timeoutSeconds: 3
    periodSeconds: 10
```

---

### Issue 11 — Rolling update deadlock after force-deleting OOMKilling pod

**Symptom**
After force-deleting the old OOMKilling Grafana pod, two Grafana pods appeared — a new pod from the rolling update (new ReplicaSet) and a replacement pod from the old ReplicaSet — both competing for the same resources and blocking each other.

**Root cause**
Force-deleting a pod in a Deployment causes its controlling ReplicaSet to immediately create a replacement to maintain the declared replica count. The rolling update was simultaneously trying to schedule the upgraded pod from the new ReplicaSet. Both pods were now pending, competing for the same node resources.

**Debugging commands**
```bash
# See which ReplicaSets are active and how many pods each manages
kubectl get replicasets -n monitoring

# Watch all pods to understand the scheduling sequence
kubectl get pods -n monitoring -w
```

**Fix**
Waited for the new ReplicaSet's pod to reach `3/3 Ready`. At that point the rolling update controller automatically terminated the old ReplicaSet's replacement pod, resolving the conflict without manual intervention.

---

## General Debugging Reference

### Kubernetes pod diagnostics

```bash
# List all pods with status across all namespaces
kubectl get pods -A

# Watch pods in real time
kubectl get pods -n <namespace> -w

# Describe a pod — shows events, resource requests, probe config
kubectl describe pod <pod-name> -n <namespace>

# Tail container logs
kubectl logs <pod-name> -n <namespace> -c <container-name> --tail=50

# Follow logs in real time
kubectl logs <pod-name> -n <namespace> -f

# See resource usage (requires metrics-server — enabled on GKE by default)
kubectl top pods -n <namespace>
kubectl top nodes
```

### Deployment and rollout management

```bash
# Check rollout status
kubectl rollout status deployment/<name>

# View rollout history
kubectl rollout history deployment/<name>

# Roll back to previous version
kubectl rollout undo deployment/<name>

# Restart all pods in a deployment (triggers a rolling restart)
kubectl rollout restart deployment/<name>

# Force-delete a stuck pod (ReplicaSet will recreate it)
kubectl delete pod <pod-name> -n <namespace>
```

### Helm troubleshooting

```bash
# List all Helm releases across namespaces
helm list -A

# Check the status of a release
helm status <release-name> -n <namespace>

# View the rendered manifests for a release
helm get manifest <release-name> -n <namespace>

# Uninstall a release
helm uninstall <release-name> -n <namespace>

# Upgrade an existing release with new values
helm upgrade <release-name> <chart> -f values.yaml -n <namespace>

# Install or upgrade (idempotent)
helm upgrade --install <release-name> <chart> -f values.yaml -n <namespace> --create-namespace
```

### Node and scheduling diagnostics

```bash
# Check allocatable resources and what is currently scheduled on each node
kubectl describe nodes | grep -A 15 "Allocated resources"

# List all DaemonSet pods (these run on every node and consume baseline resources)
kubectl get pods -A -o wide | grep -E "node-exporter|fluentbit|kube-proxy"

# See why a pod is Pending (look at Events section)
kubectl describe pod <pending-pod-name>
```

### GCP and gcloud

```bash
# Verify active account and project
gcloud auth list
gcloud config list

# Re-authenticate if credentials are broken
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID

# Reconnect kubectl to GKE cluster
gcloud container clusters get-credentials gke-pipeline-cluster \
  --zone us-central1-a --project YOUR_PROJECT_ID

# Check which GCP APIs are enabled
gcloud services list --enabled

# Enable a GCP API
gcloud services enable <api>.googleapis.com
```

### Terraform

```bash
# Preview changes without applying
terraform plan

# Apply changes
terraform apply

# Destroy all resources (use with caution)
terraform destroy

# Show current state
terraform show

# Re-initialize after provider or backend changes
terraform init -upgrade
```
