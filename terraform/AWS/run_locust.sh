#!/bin/bash

# exit when any command fails
set -e

# set locust master host
declare master=$(terraform output locust_master_dns | tr -d '"')

# List of locust worker hosts
declare -a workerList=$(terraform output locust_workernodes_dns | sed -r 's/[][,]//g' )

# set workers per worker node
declare workerCount=$(terraform output worker_per_node)

declare -a locustFiles=$(terraform output locust_files | sed -r 's/,/" "/g')

# set ssh keyfile path
declare sshKeyPath=$(terraform output ssh_keyfile_path | tr -d '"')

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