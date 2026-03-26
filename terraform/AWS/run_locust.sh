#!/bin/bash

# exit when any command fails
set -e

# Script is intended to be run from terraform/AWS; config.json lives at ../../config.json (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/../../config.json"

# set locust master host
declare master=$(terraform output locust_master_dns | tr -d '"')

# List of locust worker hosts
declare -a workerList=$(terraform output locust_workernodes_dns | sed -r 's/[][,]//g' )

# set workers per worker node
declare workerCount=$(terraform output worker_per_node)

declare -a locustFiles=$(terraform output locust_files | sed -r 's/,/" "/g')

# set ssh keyfile path
declare sshKeyPath=$(terraform output ssh_keyfile_path | tr -d '"')

# --- Populate config.json from Terraform outputs (lakebase + service principal) before syncing to compute ---
echo "Writing Terraform outputs into config.json..."
LAKEBASE_PROJECT_ID=$(terraform output -raw lakebase_project_id)
LAKEBASE_BRANCH_ID=$(terraform output -raw lakebase_branch_id)
LAKEBASE_ENDPOINT_ID="primary"
SP_ID=$(terraform output -raw databricks_service_principal_id)
SP_SECRET=$(terraform output -raw service_principal_secret)

if [ ! -f "$CONFIG_PATH" ]; then
  echo '{"workspace":{"host":"","client_id":"","client_secret":""},"lakebase":{"mode":"autoscale","database":"databricks_postgres"}}' > "$CONFIG_PATH"
fi

# Merge Terraform outputs into config (preserves existing workspace.host and other fields)
jq --arg project_id "$LAKEBASE_PROJECT_ID" \
   --arg branch_id "$LAKEBASE_BRANCH_ID" \
   --arg endpoint_id "$LAKEBASE_ENDPOINT_ID" \
   --arg user "$SP_ID" \
   --arg client_id "$SP_ID" \
   --arg client_secret "$SP_SECRET" \
   '.workspace.client_id = $client_id | .workspace.client_secret = $client_secret | .lakebase.project_id = $project_id | .lakebase.branch_id = $branch_id | .lakebase.endpoint_id = $endpoint_id | .lakebase.user = $user | .lakebase.mode = "autoscale" | .lakebase.database = (.lakebase.database // "databricks_postgres")' \
   "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"

echo "config.json updated with lakebase and service principal from Terraform."

# starting locust master
echo "starting master on ${master}..."

echo "sync requirements.txt"

rsync -Pav -e "ssh -o StrictHostKeyChecking=accept-new -i ${sshKeyPath}" ../../requirements.txt ubuntu@${master}:/home/ubuntu/requirements.txt

echo "syncing locust files"
for file in ${locustFiles[@]}; do
    file=$(echo ${file} | tr -d '\"')
    echo "syncing file ${file}"
    rsync -Pav -e "ssh -o StrictHostKeyChecking=accept-new -i ${sshKeyPath}" ../../${file} ubuntu@${master}:/home/ubuntu/${file}
done

ssh -o StrictHostKeyChecking=accept-new -i ${sshKeyPath} ubuntu@${master} << EOF
rm master.log
sudo apt-get update
sudo apt-get install python3-pip python3.12-venv -y
python3.12 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
nohup locust --master -f locust.py >> master.log 2>&1 &
EOF

echo "done!"

# starting users on each worker node
for host in ${workerList[@]}; do
    host=$(echo ${host} | tr -d '"')
    echo "starting worker on ${host}"

    rsync -Pav -e "ssh -o StrictHostKeyChecking=accept-new -i ${sshKeyPath}" ../../requirements.txt ubuntu@${host}:/home/ubuntu/requirements.txt

    for file in ${locustFiles[@]}; do
        file=$(echo ${file} | tr -d '"') 
        echo "syncing file ${file}" 
        rsync -Pav -e "ssh -o StrictHostKeyChecking=accept-new -i ${sshKeyPath}" ../../${file} ubuntu@${host}:/home/ubuntu/${file} 
    done

    ssh -o StrictHostKeyChecking=accept-new -i ${sshKeyPath} ubuntu@${host} << EOF
    rm worker*.log
    sudo apt-get update
    sudo apt-get install python3-pip python3.12-venv -y
    python3.12 -m venv venv
    source venv/bin/activate
    pip3 install -r requirements.txt
    for ((c=1; c<="${workerCount}"; c++))
    do
        nohup locust --worker --master-host="${master}" -f locust.py >> worker"$c".log 2>&1 &
        sleep 1
    done
EOF
done

echo "done!"

echo "Find the Locust dashboard at http://${master}:8089"