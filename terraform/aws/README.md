# AWS deployment paths

| Path | Compute | Deploy script |
|------|---------|---------------|
| [`ec2/`](ec2/) | EC2 master + workers | `./run_locust.sh` |
| [`eks/`](eks/) | EKS cluster + Kubernetes | `./deploy_locust.sh` |

Shared Terraform modules live in [`../modules/`](../modules/) (`lakebase`, `databricks`).

**Migrating from the old `terraform/AWS/` layout:** EC2 state and config now live under [`ec2/`](ec2/). Run `terraform init` from that directory before your next apply.
