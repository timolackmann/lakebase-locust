#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
CONFIG_PATH="${SCRIPT_DIR}/../../../config.json"

SSH_OPTS=(
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=15
    -o BatchMode=yes
)

RSYNC_SSH="ssh ${SSH_OPTS[*]}"

master=$(terraform output -raw locust_master_dns)
workerCount=$(terraform output -raw worker_per_node)
sshKeyPath=$(terraform output -raw ssh_keyfile_path)

# Build local file list for rsync (requirements.txt + locustFiles from Terraform)
rsync_files=( "${SCRIPT_DIR}/../../../requirements.txt" )
while IFS= read -r file; do
    [ -n "${file}" ] || continue
    rsync_files+=( "${SCRIPT_DIR}/../../../${file}" )
done < <(terraform output -raw locust_files | tr ',' '\n')

wait_all() {
    local fail=0
    for pid in "$@"; do
        wait "${pid}" || fail=1
    done
    return "${fail}"
}

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

provision_host() {
    local host=$1
    echo "[${host}] syncing files..."
    rsync -Pav -e "ssh ${SSH_OPTS[*]} -i ${sshKeyPath}" \
        "${rsync_files[@]}" "ubuntu@${host}:/home/ubuntu/"

    echo "[${host}] installing dependencies..."
    ssh "${SSH_OPTS[@]}" -i "${sshKeyPath}" "ubuntu@${host}" bash -s <<'REMOTE'
set -euo pipefail
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pip python3.12-venv
python3.12 -m venv venv
source venv/bin/activate
pip3 install -q -r requirements.txt
REMOTE
    echo "[${host}] provisioned"
}

start_master() {
    local host=$1
    echo "[${host}] starting locust master..."
    ssh "${SSH_OPTS[@]}" -i "${sshKeyPath}" "ubuntu@${host}" bash -s <<'REMOTE'
set -euo pipefail
rm -f master.log
source venv/bin/activate
nohup locust --master -f locust.py >> master.log 2>&1 &
REMOTE
    echo "[${host}] master started"
}

start_workers_on_host() {
    local host=$1
    local count=$2
    local master_host=$3
    echo "[${host}] starting ${count} locust workers..."
    ssh "${SSH_OPTS[@]}" -i "${sshKeyPath}" "ubuntu@${host}" bash -s "${count}" "${master_host}" <<'REMOTE'
set -euo pipefail
worker_count=$1
master_host=$2
rm -f worker*.log
source venv/bin/activate
for ((c = 1; c <= worker_count; c++)); do
    nohup locust --worker --master-host="${master_host}" -f locust.py >> "worker${c}.log" 2>&1 &
    sleep 1
done
REMOTE
    echo "[${host}] workers started"
}

wait_for_master() {
    local host=$1
    # Check via SSH only (port 22). We do not connect to 5557 from your laptop — SG allows
    # 5557 only between Locust nodes. This polls for the master process on the EC2 instance.
    echo "Waiting for locust master process on ${host}..."
    for _ in $(seq 1 60); do
        if ssh "${SSH_OPTS[@]}" -i "${sshKeyPath}" "ubuntu@${host}" \
            "pgrep -f '[l]ocust.*--master' >/dev/null"; then
            echo "Master is ready."
            sleep 2
            return 0
        fi
        sleep 1
    done
    echo "WARNING: locust master process not confirmed; workers may need a moment to connect." >&2
}

# --- Phase 1: provision all VMs in parallel (rsync + apt + pip) ---
echo "Provisioning all nodes in parallel..."
provision_pids=()
provision_host "${master}" &
provision_pids+=($!)

while IFS= read -r host; do
    [ -n "${host}" ] || continue
    provision_host "${host}" &
    provision_pids+=($!)
done < <(terraform output -json locust_workernodes_dns | jq -r '.[]')

wait_all "${provision_pids[@]}"

# --- Phase 2: start master, then workers (workers need master up) ---
start_master "${master}"
wait_for_master "${master}"

echo "Starting workers on all nodes in parallel..."
worker_pids=()
while IFS= read -r host; do
    [ -n "${host}" ] || continue
    start_workers_on_host "${host}" "${workerCount}" "${master}" &
    worker_pids+=($!)
done < <(terraform output -json locust_workernodes_dns | jq -r '.[]')

wait_all "${worker_pids[@]}"

echo "done!"
echo "Find the Locust dashboard at http://${master}:8089"
