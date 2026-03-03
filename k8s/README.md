# Locust Lakebase – Kubernetes

Run Locust load tests on Kubernetes using a single image for master and workers. This folder contains manifests and scripts to build the image and deploy the cluster.

## Build and push image

Build and push the image to GCP Artifact Registry. The script builds for **linux/amd64** so the image runs on typical GKE/cloud nodes (avoids "exec format error" when building on Apple Silicon). Run from the **repository root**:

```bash
./k8s/build-and-push.sh
```

Optional env overrides: `GCP_PROJECT_ID`, `ARTIFACT_REGISTRY_REGION` (default `europe-west1`), `ARTIFACT_REGISTRY_REPO` (default `locust`), `IMAGE_NAME` (default `locust-lakebase`), `IMAGE_TAG` (default `latest`). Create the Artifact Registry repository first—see comments in the script.

Update the `image` field in `locust-master-pod.yaml` and `locust-worker-deployment.yaml` to match your registry and tag.

## Resources

Applying the manifests in this folder creates three resources:

1. **Locust master Pod** (`locust-master-pod.yaml`) – A single Pod that runs the Locust master. It coordinates the test and serves the web UI on port 8089. It expects ConfigMaps `locust-script` (e.g. from `locust.py`) and `locust-config` (e.g. from `config.json`). Create them from the repo root before applying:
   ```bash
   kubectl create configmap locust-script --from-file=locust.py=./locust.py
   kubectl create configmap locust-config --from-file=config.json=./config.json
   kubectl apply -f k8s/locust-master-pod.yaml
   ```

2. **Locust master Service** (`master-service.yaml`) – A Service named `master` that exposes the master Pod so worker Pods can connect to it (ports 8089, 5557, 5558). Apply with:
   ```bash
   kubectl apply -f k8s/master-service.yaml
   ```

3. **Locust worker Deployment** (`locust-worker-deployment.yaml`) – A Deployment that runs Locust workers. Workers connect to the master via the `master` Service. Uses the same ConfigMaps as the master. Apply after the master Pod and Service are running:
   ```bash
   kubectl apply -f k8s/locust-worker-deployment.yaml
   ```

## Exposing the Locust UI and scaling workers

- **Locust web UI** – Port-forward the master Service to access the UI on your machine:
  ```bash
  kubectl port-forward service/master 8089:8089
  ```
  Then open http://localhost:8089 in your browser.

- **Scale worker nodes** – Change the number of worker replicas as needed:
  ```bash
  kubectl scale deployment locust-worker --replicas 20
  ```

## Databricks IP access list

If your Databricks workspace uses an IP allow list, the cluster’s outbound IPs must be allowed. Use **`k8s-cluster-ip-access.sh`** (from this folder or the repo root) to collect your Kubernetes cluster’s node external IPs and create a new IP access list in Databricks:

```bash
./k8s-cluster-ip-access.sh
```

- **Optional:** `-p, --profile PROFILE` for the Databricks CLI profile; `-l, --label LABEL` for the access list label (default: `k8s-cluster-egress`).
- **Prerequisites:** `kubectl` configured for your cluster and Databricks CLI installed and authenticated (e.g. `databricks auth login`).
