#!/usr/bin/env bash
# Delete Locust ConfigMaps, master pod, master service, and worker deployment,
# then recreate them from the current repo. Run from repo root or any directory (script locates repo root).
#
# Prerequisites: kubectl configured for your cluster; LOCUST_IMAGE set to your pushed image.
#
# Usage:
#   export LOCUST_IMAGE=your-registry/locust-lakebase:latest
#   export WORKER_REPLICAS=3   # optional, default 3
#   ./refresh-deployment.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

if [[ -z "${LOCUST_IMAGE:-}" ]]; then
  echo "Error: set LOCUST_IMAGE to your container image (e.g. export LOCUST_IMAGE=gcr.io/project/locust-lakebase:latest)" >&2
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "Error: envsubst is required (install gettext)." >&2
  exit 1
fi

export WORKER_REPLICAS="${WORKER_REPLICAS:-3}"

echo "Deleting existing Locust resources (ignore-not-found)..."

kubectl delete deployment locust-worker --ignore-not-found
kubectl delete pod locust-master --ignore-not-found
kubectl delete service master --ignore-not-found
kubectl delete configmap locust-script --ignore-not-found
kubectl delete configmap locust-config --ignore-not-found

echo "Recreating ConfigMaps from current locust.py and config.json..."
kubectl create configmap locust-script --from-file=locust.py="${REPO_ROOT}/locust.py"
kubectl create configmap locust-config --from-file=config.json="${REPO_ROOT}/config.json"

echo "Applying master pod and service..."
envsubst < "${REPO_ROOT}/k8s/locust-master-pod.yaml" | kubectl apply -f -
kubectl apply -f "${REPO_ROOT}/k8s/master-service.yaml"

echo "Applying worker deployment..."
envsubst < "${REPO_ROOT}/k8s/locust-worker-deployment.yaml" | kubectl apply -f -

echo "Done. Master: pod locust-master, service master. Workers: deployment locust-worker."
echo "Image: ${LOCUST_IMAGE}"
