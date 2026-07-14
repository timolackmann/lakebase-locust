# Locust Lakebase – Kubernetes (bring your own cluster)

This guide is for you if you already have a Kubernetes cluster (GKE, EKS, minikube, etc.) and want to run [Locust](https://locust.io/) load tests against Databricks Lakebase from pods. The master and workers share one container image. This folder holds cloud-neutral manifests and the Dockerfile.

For the **full-stack AWS EKS path** (Terraform provisions the cluster, Lakebase, and service principal), see [`../terraform/aws/eks/README.md`](../terraform/aws/eks/README.md).

For local setup, `config.json`, and Lakebase authentication, see the [repository README](../README.md).

**Before you start**

- **Image:** Docker and a container registry (Google Artifact Registry, Amazon ECR, or any registry your cluster can pull from).
- **Cluster:** `kubectl` configured to talk to your target cluster.
- **Test files:** `locust.py` and `config.json` at the [repository root](../README.md) (copy from [`config.example.json`](../config.example.json); used when creating ConfigMaps).
- **Service principal:** run [`setup_service_principal.py`](../setup_service_principal.py) to create a dedicated service principal and populate `config.json` before creating the `locust-config` ConfigMap. See [Service principal setup (Kubernetes)](../README.md#service-principal-setup-kubernetes) in the repository README.

## Table of contents

- [Build and push image](#build-and-push-image)
- [Resources](#resources)
- [Exposing the Locust UI and scaling workers](#exposing-the-locust-ui-and-scaling-workers)
- [Databricks IP access list](#databricks-ip-access-list)

---

## Build and push image

Build and push the image to your registry. Scripts target **linux/amd64** so the image runs on typical cloud nodes (avoids `exec format error` on Apple Silicon).

**Google Cloud Artifact Registry** — from the repository root:

```bash
./scripts/build-and-push-gcr.sh
```

Prerequisites and one-time setup are documented in the comments in [`../scripts/build-and-push-gcr.sh`](../scripts/build-and-push-gcr.sh). The legacy wrapper [`build-and-push.sh`](build-and-push.sh) calls the same script.

**Amazon ECR** — if you manage your own EKS cluster:

```bash
export ECR_REPOSITORY_URL=123456789.dkr.ecr.us-east-1.amazonaws.com/locust-lakebase
export AWS_REGION=us-east-1
./scripts/build-and-push-ecr.sh
```

Override defaults with environment variables documented in each script.

After pushing, set `LOCUST_IMAGE` to your full image reference (registry URL + tag) before applying manifests.

---

## Resources

Apply things in this order: create the ConfigMaps, then the master Pod, then the Service, then the worker Deployment.

Manifests use `envsubst` for `LOCUST_IMAGE` and `WORKER_REPLICAS`:

```bash
export LOCUST_IMAGE=your-registry/locust-lakebase:latest
export WORKER_REPLICAS=3
```

1. **Locust master Pod** ([`locust-master-pod.yaml`](locust-master-pod.yaml)) – One Pod runs the Locust **master**: it coordinates the test and serves the web UI on port **8089**. It needs ConfigMaps named `locust-script` (from `locust.py`) and `locust-config` (from `config.json`). From the repository root:

   ```bash
   kubectl create configmap locust-script --from-file=locust.py=./locust.py
   kubectl create configmap locust-config --from-file=config.json=./config.json
   envsubst < k8s/locust-master-pod.yaml | kubectl apply -f -
   ```

2. **Locust master Service** ([`master-service.yaml`](master-service.yaml)) – A Service named `master` reaches the master Pod so workers can connect (ports **8089**, **5557**, **5558**):

   ```bash
   kubectl apply -f k8s/master-service.yaml
   ```

3. **Locust worker Deployment** ([`locust-worker-deployment.yaml`](locust-worker-deployment.yaml)) – Runs Locust **workers**. They talk to the master through the `master` Service and use the same ConfigMaps as the master:

   ```bash
   envsubst < k8s/locust-worker-deployment.yaml | kubectl apply -f -
   ```

Or use [`../refresh-deployment.sh`](../refresh-deployment.sh) from the repo root (requires `LOCUST_IMAGE`).

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

- **Private EKS clusters** typically egress via NAT gateway Elastic IPs, not node `ExternalIP`. Use the [Terraform EKS path](../terraform/aws/eks/README.md) to wire NAT EIPs into the allow list, or add those IPs manually.
- **Optional flags:** `-p, --profile PROFILE` (Databricks CLI profile); `-l, --label LABEL` (access list label; default `k8s-cluster-egress`).
- **Prerequisites:** `kubectl` configured for your cluster; Databricks CLI installed and signed in (for example `databricks auth login`).
