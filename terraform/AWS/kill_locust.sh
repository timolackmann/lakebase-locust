#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

master=$(terraform output -raw locust_master_dns)
sshKeyPath=$(terraform output -raw ssh_keyfile_path)

SSH_OPTS=(
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=15
    -o BatchMode=yes
)

kill_locust_on_host() {
    local host=$1
    echo "  -> ${host}"
    if ssh "${SSH_OPTS[@]}" -i "${sshKeyPath}" "ubuntu@${host}" "pkill -f '[l]ocust' || true"; then
        echo "     ok"
    else
        echo "     WARNING: SSH or kill failed on ${host} (continuing)" >&2
    fi
}

echo "killing worker nodes"
while IFS= read -r host; do
    [ -n "${host}" ] || continue
    kill_locust_on_host "${host}"
done < <(terraform output -json locust_workernodes_dns | jq -r '.[]')

if [ "${1:-}" = "all" ]; then
    echo "killing locust master"
    kill_locust_on_host "${master}"
fi

echo "done!"
