#!/usr/bin/env bash
# Build the Locust Lakebase image and push it to Google Cloud Artifact Registry.
#
# Prerequisites:
#   - Docker
#   - gcloud CLI logged in (gcloud auth login)
#   - Artifact Registry repository created, e.g.:
#     gcloud artifacts repositories create LOCUST_REPO --repository-format=docker \
#       --location=REGION --description="Locust images"
#   - Docker configured for Artifact Registry (one-time):
#     gcloud auth configure-docker REGION-docker.pkg.dev --quiet
#
# Usage:
#   ./k8s/build-and-push.sh
#
# Override via environment:
#   GCP_PROJECT_ID     - GCP project (default: from gcloud config)
#   ARTIFACT_REGISTRY_REGION - Region, e.g. europe-west1 (default: europe-west1)
#   ARTIFACT_REGISTRY_REPO   - Repository name (default: locust)
#   IMAGE_NAME         - Image name in the repo (default: locust-lakebase)
#   IMAGE_TAG          - Tag (default: latest)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
ARTIFACT_REGISTRY_REGION="${ARTIFACT_REGISTRY_REGION:-europe-west1}"
ARTIFACT_REGISTRY_REPO="${ARTIFACT_REGISTRY_REPO:-locust}"
IMAGE_NAME="${IMAGE_NAME:-locust-lakebase}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
  echo "Error: GCP_PROJECT_ID is not set and 'gcloud config get-value project' did not return a project." >&2
  echo "Set GCP_PROJECT_ID or run: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: Cannot connect to the Docker daemon. Is it running?" >&2
  echo "  - Colima:  colima start" >&2
  echo "  - Docker Desktop: start the app from Applications" >&2
  exit 1
fi

REGISTRY="${ARTIFACT_REGISTRY_REGION}-docker.pkg.dev"
FULL_IMAGE="${REGISTRY}/${GCP_PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

# Build for linux/amd64 so the image runs on typical GKE/cloud nodes (avoids exec format error on ARM-built images)
echo "Building image for linux/amd64 from ${REPO_ROOT} (Dockerfile: k8s/Dockerfile)"
docker build --platform linux/amd64 -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE_NAME:$IMAGE_TAG" -t "$FULL_IMAGE" "$REPO_ROOT"

echo "Pushing to Artifact Registry: $FULL_IMAGE"
docker push "$FULL_IMAGE"

echo "Done. Image: $FULL_IMAGE"
