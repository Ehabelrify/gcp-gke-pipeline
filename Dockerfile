# ── Dockerfile ────────────────────────────────────────────────────────────────
# Builds the FastAPI application into a container image.
# The image is pushed to Google Artifact Registry and pulled by GKE nodes.

# python:3.12-slim is the official Python image without dev tools.
# "slim" strips compilers and docs — roughly 60 MB vs 900 MB for the full image.
FROM python:3.12-slim

# Set the working directory inside the container.
# All subsequent COPY and RUN commands operate relative to /app.
WORKDIR /app

# Copy requirements.txt before the source code.
# Docker caches each layer independently. Copying requirements first means
# a code-only change reuses the cached pip install layer — faster rebuilds.
COPY app/requirements.txt .

# Install Python dependencies.
# --no-cache-dir prevents pip from writing a local cache inside the image,
# keeping the image smaller.
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application source code into the container.
COPY app/ .

# Document which port the app listens on.
# EXPOSE is metadata only — actual port binding happens in the k8s Service.
EXPOSE 8000

# Start the FastAPI app with uvicorn when the container launches.
# --host 0.0.0.0 binds to all network interfaces (required inside a container —
# 127.0.0.1 would only be reachable from within the container itself).
# --port 8000 matches the EXPOSE above.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]