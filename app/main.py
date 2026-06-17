import os
import hvac                   # HashiCorp Vault client
from fastapi import FastAPI, HTTPException

# Create the FastAPI application instance.
# title and version show up in the auto-generated /docs UI.
app = FastAPI(
    title="GCP GKE Pipeline Demo",
    version="1.0.0",
    description="FastAPI service running on GKE, deployed via GitHub Actions CI/CD",
)


@app.get("/")
def root():
    """Root endpoint — returns basic service info."""
    return {
        "service": "gcp-gke-pipeline",
        "status": "running",
        "description": "FastAPI app deployed on GKE via GitHub Actions CI/CD",
    }


@app.get("/health")
def health():
    """
    Health check endpoint.
    Kubernetes liveness and readiness probes will call this.
    Returning 200 tells the cluster the pod is healthy.
    """
    return {"status": "healthy"}


@app.get("/items")
def list_items():
    """Sample data endpoint — demonstrates a real API response."""
    return {
        "items": [
            {"id": 1, "name": "item-alpha", "value": 100},
            {"id": 2, "name": "item-beta", "value": 200},
            {"id": 3, "name": "item-gamma", "value": 300},
        ]
    }


@app.get("/secret")
def get_secret():
    """
    Reads the 'db_password' secret from HashiCorp Vault's KV v2 engine.

    VAULT_ADDR and VAULT_TOKEN are injected as environment variables by the
    Kubernetes Deployment manifest. Inside the cluster, Vault is reachable at
    http://vault.vault.svc.cluster.local:8200 — the DNS format is:
    <service-name>.<namespace>.svc.cluster.local

    If Vault is unreachable (e.g. running locally without Vault), the endpoint
    returns a clear error message rather than crashing the whole app.
    """
    vault_addr = os.getenv("VAULT_ADDR", "http://vault.vault.svc.cluster.local:8200")
    vault_token = os.getenv("VAULT_TOKEN", "root")

    try:
        # Create an authenticated Vault client
        client = hvac.Client(url=vault_addr, token=vault_token)

        # Read from the KV v2 secret engine.
        # KV v2 wraps the actual data under response["data"]["data"].
        # The path "app" maps to the secret we wrote with: vault kv put secret/app ...
        response = client.secrets.kv.v2.read_secret_version(
            path="app",
            mount_point="secret",  # the KV engine is mounted at "secret/" in dev mode
        )
        db_password = response["data"]["data"]["db_password"]
        return {"source": "vault", "db_password": db_password}

    except Exception as e:
        # Surface the error clearly rather than returning a 500 with no context
        raise HTTPException(status_code=503, detail=f"Could not reach Vault: {str(e)}")