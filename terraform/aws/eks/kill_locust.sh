#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REGION=$(terraform output -raw region)
CLUSTER=$(terraform output -raw cluster_name)
PROFILE=$(terraform output -raw aws_profile)

aws eks update-kubeconfig --name "${CLUSTER}" --region "${REGION}" --profile "${PROFILE}"

echo "Deleting Locust worker deployment..."
kubectl delete deployment locust-worker --ignore-not-found

echo "Deleting Locust master pod and service..."
kubectl delete pod locust-master --ignore-not-found
kubectl delete service master --ignore-not-found

if [ "${1:-}" = "all" ]; then
  echo "Deleting ConfigMaps..."
  kubectl delete configmap locust-script locust-config --ignore-not-found
fi

echo "done!"
