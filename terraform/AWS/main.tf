terraform {
  required_version = ">= 1.14.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.110"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.awsProfile
}

provider "databricks" {
  profile = var.databricksProfile
}

module "locust" {
  source                    = "./modules/locust_infrastructure"
  region                    = var.region
  locustMasterInstanceType = var.locustMasterInstanceType
  locustWorkerInstanceType  = var.locustWorkerInstanceType
  keyName                   = var.keyName
  keyPath                   = var.keyPath
  awsSubnetId               = var.awsSubnetId
  awsVpcId                  = var.awsVpcId
  workernodeCount           = var.workernodeCount
  allowedIngressCidr       = var.allowedIngressCidr
}

module "lakebase" {
  source                   = "./modules/lakebase"
  lakebaseProjectName      = var.lakebaseProjectName
  lakebaseProjectId        = var.LakebaseProjectId
  lakebasePgVersion        = var.lakebasePgVersion
  lakebaseEndpoint_min_cu  = var.lakebaseEndpoint_min_cu
  lakebaseEndpoint_max_cu  = var.lakebaseEndpoint_max_cu
  lakebaseSuspendTimeout   = var.lakebaseSuspendTimeout
}

module "databricks" {
  source                        = "./modules/databricks"
  locust_external_ips            = module.locust.locust_external_ips
  service_principal_display_name = var.databricks_service_principal_display_name
  ip_access_list_label          = var.databricks_ip_access_list_label

  depends_on = [module.locust]
}

# Optional: run SQL on Lakebase Postgres to grant the service principal OAuth access.
# Set run_grant_sp_to_lakebase = true and provide lakebase_branch_id + lakebase_endpoint_id
# (create branch/endpoint in UI or CLI first, or add databricks_postgres_branch/endpoint to the lakebase module).
resource "null_resource" "grant_sp_to_lakebase" {
  count = var.run_grant_sp_to_lakebase && var.lakebase_branch_id != "" && var.lakebase_endpoint_id != "" ? 1 : 0

  triggers = {
    project_id   = module.lakebase.project_id
    branch_id    = var.lakebase_branch_id
    endpoint_id  = var.lakebase_endpoint_id
    sp_id        = module.databricks.service_principal_id
    databricks   = var.databricksProfile
    lakebase_db  = var.lakebase_database
  }

  provisioner "local-exec" {
    command = <<-EOT
      python3 ${path.module}/scripts/grant_service_principal_to_lakebase.py \
        --project-id "${module.lakebase.project_id}" \
        --branch-id "${var.lakebase_branch_id}" \
        --endpoint-id "${var.lakebase_endpoint_id}" \
        --service-principal-id "${module.databricks.service_principal_id}" \
        --profile "${var.databricksProfile}" \
        --database "${var.lakebase_database}"
    EOT
  }

  depends_on = [module.lakebase, module.databricks]
}