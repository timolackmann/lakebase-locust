# AWS EKS – full-stack Locust deployment

This path provisions an **EKS cluster**, **ECR repository**, **Lakebase autoscale project**, and **Databricks service principal** with one `terraform apply`, then deploys Locust with `./deploy_locust.sh`.

For bring-your-own Kubernetes (any cloud), see [`../../../k8s/README.md`](../../../k8s/README.md).

For the EC2-based AWS path, see [`../ec2/`](../ec2/).

## Prerequisites

- AWS CLI, `kubectl`, Docker, Terraform (>= 1.14.6), Databricks CLI
- An **existing VPC** with:
  - **Private subnets** for the EKS cluster and node group (at least two AZs recommended)
  - **NAT gateways** for outbound traffic (egress IPs are used for Databricks IP allow lists)
- Subnets tagged for EKS, for example:
  - `kubernetes.io/cluster/<clusterName>` = `shared`
  - `kubernetes.io/role/internal-elb` = `1`
- [`config.json`](../../../config.json) at the repo root with `workspace.host` set (other fields are filled by `deploy_locust.sh`)

## Quick start

```bash
cd terraform/aws/eks
cp terraform.tfvars.template terraform.tfvars   # fill VPC, subnets, profiles
terraform init && terraform apply
./deploy_locust.sh
```

Open the Locust UI:

```bash
kubectl port-forward service/master 8089:8089
```

Then visit [http://localhost:8089](http://localhost:8089).

## IP access list (two-step apply)

NAT gateway egress IPs are discovered from your VPC after the cluster exists. On the first apply, keep `enable_ip_access_list = false`. After NAT gateways are present, set `enable_ip_access_list = true` and run `terraform apply` again.

## Teardown

```bash
./kill_locust.sh all    # remove Locust workloads from the cluster
terraform destroy       # delete EKS, ECR, Lakebase, service principal
```

## What Terraform creates

| Component | Module |
|-----------|--------|
| EKS cluster + managed node group | `modules/eks_infrastructure` |
| ECR repository | `modules/eks_infrastructure` |
| Lakebase project, branch, endpoint | `../../modules/lakebase` |
| Service principal + OAuth role | `../../modules/databricks` |

## Scripts

| Script | Purpose |
|--------|---------|
| [`deploy_locust.sh`](deploy_locust.sh) | Write `config.json`, build/push image to ECR, apply K8s manifests |
| [`kill_locust.sh`](kill_locust.sh) | Delete Locust pods/deployment; `kill_locust.sh all` also removes ConfigMaps |
| [`../../../scripts/build-and-push-ecr.sh`](../../../scripts/build-and-push-ecr.sh) | Build and push the Locust Docker image (called by `deploy_locust.sh`) |

## Variables

See [`terraform.tfvars.template`](terraform.tfvars.template) for all inputs. Key EKS-specific values:

- `privateSubnetIds` – where the cluster and nodes run
- `workerReplicas` – Locust worker pod count (also sizes the node group)
- `clusterName`, `nodeInstanceType`, `kubernetesVersion`

Lakebase and Databricks variables match the [EC2 path](../ec2/terraform.tfvars.template).
