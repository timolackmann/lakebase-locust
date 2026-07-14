#!/usr/bin/env bash
# Build the Locust Lakebase image and push it to Amazon ECR.
#
# Prerequisites:
#   - Docker
#   - AWS CLI authenticated (aws configure or AWS_PROFILE)
#   - ECR repository already created (terraform/aws/eks provisions one)
#
# Usage:
#   ECR_REPOSITORY_URL=123456789.dkr.ecr.us-east-1.amazonaws.com/locust-lakebase ./scripts/build-and-push-ecr.sh
#
# Override via environment:
#   ECR_REPOSITORY_URL - Full ECR repo URL without tag (required unless AWS_ACCOUNT_ID + AWS_REGION + ECR_REPO_NAME set)
#   AWS_ACCOUNT_ID     - AWS account ID (optional if ECR_REPOSITORY_URL unset)
#   AWS_REGION         - AWS region (optional if ECR_REPOSITORY_URL unset)
#   ECR_REPO_NAME      - ECR repository name (default: locust-lakebase)
#   IMAGE_TAG          - Tag (default: latest)
#   AWS_PROFILE        - AWS CLI profile
#   PIP_INDEX_URL      - forwarded into docker build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-latest}"
ECR_REPO_NAME="${ECR_REPO_NAME:-locust-lakebase}"
AWS_REGION="${AWS_REGION:-}"
AWS_PROFILE="${AWS_PROFILE:-}"

aws_cli() {
  if [[ -n "${AWS_PROFILE}" ]]; then
    aws --profile "${AWS_PROFILE}" "$@"
  else
    aws "$@"
  fi
}

if [[ -z "${ECR_REPOSITORY_URL:-}" ]]; then
  AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws_cli sts get-caller-identity --query Account --output text)}"
  if [[ -z "${AWS_REGION}" ]]; then
    echo "Error: set ECR_REPOSITORY_URL or AWS_REGION." >&2
    exit 1
  fi
  ECR_REPOSITORY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
fi

FULL_IMAGE="${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

if ! docker info >/dev/null 2>&1; then
  echo "Error: Cannot connect to the Docker daemon. Is it running?" >&2
  exit 1
fi

REGISTRY_HOST="${ECR_REPOSITORY_URL%%/*}"

if [[ -z "${AWS_REGION}" && "${ECR_REPOSITORY_URL}" =~ \.dkr\.ecr\.([^.]+)\.amazonaws\.com ]]; then
  AWS_REGION="${BASH_REMATCH[1]}"
fi

if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(aws_cli configure get region 2>/dev/null || true)"
fi

if [[ -z "${AWS_REGION}" ]]; then
  echo "Error: set AWS_REGION or use an ECR_REPOSITORY_URL that includes the region." >&2
  exit 1
fi

_pip_cfg_get() {
  local key="$1"
  command -v pip3 >/dev/null 2>&1 || return 0
  pip3 config get "$key" 2>/dev/null | tr -d '\r' | head -n1 || true
}

_PIP_INDEX_URL="${PIP_INDEX_URL:-}"
[[ -z "${_PIP_INDEX_URL}" ]] && _PIP_INDEX_URL="$(_pip_cfg_get global.index-url)"

PIP_BUILD_ARGS=()
[[ -n "${_PIP_INDEX_URL}" ]] && PIP_BUILD_ARGS+=(--build-arg "PIP_INDEX_URL=${_PIP_INDEX_URL}")

echo "Logging in to ECR (${REGISTRY_HOST})..."
aws_cli ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY_HOST}"

echo "Building image for linux/amd64 from ${REPO_ROOT} (Dockerfile: k8s/Dockerfile)"
docker build --platform linux/amd64 "${PIP_BUILD_ARGS[@]}" \
  -f "${REPO_ROOT}/k8s/Dockerfile" \
  -t "${FULL_IMAGE}" \
  "${REPO_ROOT}"

echo "Pushing to ECR: ${FULL_IMAGE}"
docker push "${FULL_IMAGE}"

echo "Done. Image: ${FULL_IMAGE}"
