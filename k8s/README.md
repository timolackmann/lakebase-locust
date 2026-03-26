# Locust Lakebase – Kubernetes

This guide is for you if you already have a Kubernetes cluster and want to run [Locust](https://locust.io/) load tests against Databricks Lakebase from pods. The master and workers share one container image. This folder holds manifests and scripts to build that image and deploy the cluster.

For local setup, `config.json`, and Lakebase authentication, see the [repository README](../README.md).

**Before you start**

- **Image:** Docker and `gcloud` (logged in), with an Artifact Registry repository created if you push images yourself.
- **Cluster:** `kubectl` configured to talk to your target cluster.
- **Test files:** `locust.py` and `config.json` at the [repository root](../README.md) (used when creating ConfigMaps).

## Table of contents

- [Build and push image](#build-and-push-image)
- [Resources](#resources)
- [Exposing the Locust UI and scaling workers](#exposing-the-locust-ui-and-scaling-workers)
- [Databricks IP access list](#databricks-ip-access-list)

---

## Build and push image

Build and push the image to Google Cloud Artifact Registry. The script targets **linux/amd64**, so the image runs on typical GKE and other amd64 nodes. That avoids an `exec format error` if you build on Apple Silicon.

Run from the **repository root**:

```bash
./k8s/build-and-push.sh
```

Prerequisites and one-time setup (Artifact Registry repo, `docker` auth) are documented in the comments in [`build-and-push.sh`](build-and-push.sh).

You can override defaults with environment variables: `GCP_PROJECT_ID`, `ARTIFACT_REGISTRY_REGION` (default `europe-west1`), `ARTIFACT_REGISTRY_REPO` (default `locust`), `IMAGE_NAME` (default `locust-lakebase`), `IMAGE_TAG` (default `latest`).

After pushing, set the `image` field in [`locust-master-pod.yaml`](locust-master-pod.yaml) and [`locust-worker-deployment.yaml`](locust-worker-deployment.yaml) to your registry URL and tag.

---

## Resources

Apply things in this order: create the ConfigMaps, then the master Pod, then the Service, then the worker Deployment.

Applying the manifests in this folder creates three resources:

1. **Locust master Pod** ([`locust-master-pod.yaml`](locust-master-pod.yaml)) – One Pod runs the Locust **master**: it coordinates the test and serves the web UI on port **8089**. It needs ConfigMaps named `locust-script` (from `locust.py`) and `locust-config` (from `config.json`). From the repository root, create them and apply the Pod:

   ```bash
   kubectl create configmap locust-script --from-file=locust.py=./locust.py
   kubectl create configmap locust-config --from-file=config.json=./config.json
   kubectl apply -f k8s/locust-master-pod.yaml
   ```

2. **Locust master Service** ([`master-service.yaml`](master-service.yaml)) – A Service named `master` reaches the master Pod so workers can connect (ports **8089**, **5557**, **5558**). Apply:

   ```bash
   kubectl apply -f k8s/master-service.yaml
   ```

3. **Locust worker Deployment** ([`locust-worker-deployment.yaml`](locust-worker-deployment.yaml)) – Runs Locust **workers**. They talk to the master through the `master` Service and use the same ConfigMaps as the master. Apply after the master Pod and Service are up:

   ```bash
   kubectl apply -f k8s/locust-worker-deployment.yaml
   ```

---

## Exposing the Locust UI and scaling workers

- **Locust web UI** – From your machine, forward port **8089** on the `master` Service:

  ```bash
  kubectl port-forward service/master 8089:8089
  ```

  Then open [http://localhost:8089](http://localhost:8089) in your browser.

- **Scale workers** – Change replica count when you need more or fewer workers:

  ```bash
  kubectl scale deployment locust-worker --replicas 20
  ```

---

## Databricks IP access list

If your Databricks workspace uses an IP allow list, allow your cluster’s outbound (egress) IPs. The script [`k8s-cluster-ip-access.sh`](k8s-cluster-ip-access.sh) collects node external IPs from Kubernetes and creates a matching IP access list in Databricks.

From the **repository root**:

```bash
./k8s/k8s-cluster-ip-access.sh
```

If your shell is already in this `k8s/` directory, run `./k8s-cluster-ip-access.sh` instead.

- **Optional flags:** `-p, --profile PROFILE` (Databricks CLI profile); `-l, --label LABEL` (access list label; default `k8s-cluster-egress`).
- **Prerequisites:** `kubectl` configured for your cluster; Databricks CLI installed and signed in (for example `databricks auth login`).
