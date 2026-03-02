#!/usr/bin/env bash
# Delete Locust ConfigMaps, master pod, master service, and worker deployment,
# then recreate them from the current repo. Run from repo root or any directory (script locates repo root).
#
# Prerequisites: kubectl configured for your cluster.
#
# Usage: ./refresh-deployment.sh

echo "Deleting existing Locust resources (ignore-not-found)..."

kubectl delete deployment locust-worker --ignore-not-found
kubectl delete pod locust-master --ignore-not-found
kubectl delete service master --ignore-not-found
kubectl delete configmap locust-script --ignore-not-found
kubectl delete configmap locust-config --ignore-not-found

echo "Recreating ConfigMaps from current locust.py and config.json..."
kubectl create configmap locust-script --from-file=locust.py
kubectl create configmap locust-config --from-file=config.json

echo "Applying master pod and service..."
kubectl apply -f "k8s/locust-master-pod.yaml"
kubectl apply -f "k8s/master-service.yaml"

echo "Applying worker deployment..."
kubectl apply -f "k8s/locust-worker-deployment.yaml"

echo "Done. Master: pod locust-master, service master. Workers: deployment locust-worker."
