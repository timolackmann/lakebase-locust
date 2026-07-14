#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CONFIG_PATH="${REPO_ROOT}/config.json"
K8S_DIR="${REPO_ROOT}/k8s"

cd "${SCRIPT_DIR}"

if ! command -v envsubst >/dev/null 2>&1; then
  echo "Error: envsubst is required (install gettext)." >&2
  exit 1
fi

# --- Populate config.json from Terraform outputs ---
echo "Writing Terraform outputs into config.json..."
LAKEBASE_PROJECT_ID=$(terraform output -raw lakebase_project_id)
LAKEBASE_BRANCH_ID=$(terraform output -raw lakebase_branch_id)
LAKEBASE_ENDPOINT_ID=$(terraform output -raw lakebase_endpoint_id)
SP_ID=$(terraform output -raw databricks_service_principal_id)
SP_SECRET=$(terraform output -raw service_principal_secret)

if [ ! -f "${CONFIG_PATH}" ]; then
  echo '{"workspace":{"host":"","client_id":"","client_secret":""},"lakebase":{"database":"databricks_postgres"}}' > "${CONFIG_PATH}"
fi

jq --arg project_id "${LAKEBASE_PROJECT_ID}" \
   --arg branch_id "${LAKEBASE_BRANCH_ID}" \
   --arg endpoint_id "${LAKEBASE_ENDPOINT_ID}" \
   --arg user "${SP_ID}" \
   --arg client_id "${SP_ID}" \
   --arg client_secret "${SP_SECRET}" \
   '.workspace.client_id = $client_id | .workspace.client_secret = $client_secret | .lakebase.project_id = $project_id | .lakebase.branch_id = $branch_id | .lakebase.endpoint_id = $endpoint_id | .lakebase.user = $user | .lakebase.database = (.lakebase.database // "databricks_postgres")' \
   "${CONFIG_PATH}" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "${CONFIG_PATH}"

echo "config.json updated."

REGION=$(terraform output -raw region)
CLUSTER=$(terraform output -raw cluster_name)
PROFILE=$(terraform output -raw aws_profile)
ECR_URL=$(terraform output -raw ecr_repository_url)
IMAGE_TAG=$(terraform output -raw image_tag)
LOCUST_IMAGE=$(terraform output -raw locust_image)
WORKER_REPLICAS=$(terraform output -raw worker_replicas)

export AWS_PROFILE="${PROFILE}"
export AWS_REGION="${REGION}"
export ECR_REPOSITORY_URL="${ECR_URL}"
export IMAGE_TAG="${IMAGE_TAG}"

echo "Configuring kubectl for cluster ${CLUSTER}..."
aws eks update-kubeconfig --name "${CLUSTER}" --region "${REGION}" --profile "${PROFILE}"

echo "Building and pushing Locust image to ECR..."
"${REPO_ROOT}/scripts/build-and-push-ecr.sh"

export LOCUST_IMAGE
export WORKER_REPLICAS

echo "Creating ConfigMaps..."
kubectl delete configmap locust-script locust-config --ignore-not-found
kubectl create configmap locust-script --from-file=locust.py="${REPO_ROOT}/locust.py"
kubectl create configmap locust-config --from-file=config.json="${CONFIG_PATH}"

echo "Applying Kubernetes manifests..."
envsubst < "${K8S_DIR}/locust-master-pod.yaml" | kubectl apply -f -
kubectl apply -f "${K8S_DIR}/master-service.yaml"
envsubst < "${K8S_DIR}/locust-worker-deployment.yaml" | kubectl apply -f -

echo "Waiting for locust-master pod..."
kubectl wait pod/locust-master --for=condition=Ready --timeout=300s

echo "done!"
echo "Locust image: ${LOCUST_IMAGE}"
echo "Open the UI: kubectl port-forward service/master 8089:8089"
echo "Then visit http://localhost:8089"
