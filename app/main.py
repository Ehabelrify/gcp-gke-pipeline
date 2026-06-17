import os
from fastapi import FastAPI

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
    Reads a secret from the DEMO_SECRET environment variable.
    In Phase 5, Vault will inject this env var into the pod.
    For now it falls back to a placeholder so the endpoint works locally too.
    """
    secret_value = os.getenv("DEMO_SECRET", "not-yet-injected-by-vault")
    return {"demo_secret": secret_value}