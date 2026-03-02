#!/usr/bin/env bash
# Get the Kubernetes cluster's outbound IP addresses (node external IPs) and create a
# new Databricks workspace IP access list (allow list) using the Databricks CLI.
#
# Prerequisites:
#   - kubectl configured for your cluster
#   - Databricks CLI installed and authenticated (e.g. databricks auth login)
#
# Usage: ./k8s-cluster-ip-access.sh [OPTIONS]
#
# Options:
#   -p, --profile PROFILE  Databricks CLI profile name (~/.databrickscfg [profile PROFILE])
#   -l, --label LABEL     Label for the new IP access list (default: k8s-cluster-egress)
#   -h, --help            Show this help and exit

set -euo pipefail

usage() {
  echo "Get Kubernetes cluster IPs and create a Databricks workspace IP access list (allow list)."
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -p, --profile PROFILE  Databricks CLI profile name (~/.databrickscfg [profile PROFILE])"
  echo "  -l, --label LABEL      Label for the new IP access list (default: k8s-cluster-egress)"
  echo "  -h, --help             Show this help and exit"
  echo ""
  echo "Example:"
  echo "  $0 --profile my-workspace --label k8s-egress"
  echo "  $0 -p my-workspace -l k8s-egress"
}

DATABRICKS_PROFILE=""
IP_ACCESS_LIST_LABEL="k8s-cluster-egress"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--profile)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        echo "Error: --profile requires a value." >&2
        exit 1
      fi
      DATABRICKS_PROFILE="$2"
      shift 2
      ;;
    -l|--label)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        echo "Error: --label requires a value." >&2
        exit 1
      fi
      IP_ACCESS_LIST_LABEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
  exit 1
fi

if ! command -v databricks &>/dev/null; then
  echo "Error: Databricks CLI is not installed or not in PATH." >&2
  echo "Install it with: pip install databricks-cli or see https://docs.databricks.com/dev-tools/cli/index.html" >&2
  exit 1
fi

# Optional CLI profile (e.g. from ~/.databrickscfg)
DATABRICKS_CLI_ARGS=()
if [[ -n "$DATABRICKS_PROFILE" ]]; then
  DATABRICKS_CLI_ARGS=(--profile "$DATABRICKS_PROFILE")
  echo "Using Databricks CLI profile: $DATABRICKS_PROFILE"
fi

if ! kubectl cluster-info &>/dev/null; then
  echo "Error: Cannot reach Kubernetes cluster (kubectl cluster-info failed)." >&2
  exit 1
fi

echo "Getting node external IPs from the current Kubernetes context..."
# Get unique ExternalIP addresses for cluster nodes (GKE / cloud nodes typically have ExternalIP)
IP_ADDRESSES=()
while IFS= read -r ip; do
  [[ -n "$ip" ]] && IP_ADDRESSES+=("$ip")
done < <(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null | tr ' ' '\n' | sort -u)

if [[ ${#IP_ADDRESSES[@]} -eq 0 ]]; then
  echo "Error: No IP addresses could be determined. For private clusters, set IP_ADDRESSES manually or ensure nodes have ExternalIP." >&2
  exit 1
fi

echo "Using ${#IP_ADDRESSES[@]} IP(s): ${IP_ADDRESSES[*]}"

# Build JSON for CLI: label, list_type, ip_addresses
IP_JSON=$(printf '%s\n' "${IP_ADDRESSES[@]}" | jq -R . | jq -s .)
BODY=$(jq -n \
  --arg label "$IP_ACCESS_LIST_LABEL" \
  --argjson ips "$IP_JSON" \
  '{label: $label, list_type: "ALLOW", ip_addresses: $ips}')

echo "Creating Databricks workspace IP access list \"$IP_ACCESS_LIST_LABEL\"..."
databricks "${DATABRICKS_CLI_ARGS[@]}" ip-access-lists create --json "$BODY"

echo "Done. It may take a few minutes for changes to take effect."
