terraform {
  required_version = ">= 1.14.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.34"
    }
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.114.2"
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

# region and keyPath are root-only (AWS provider + ssh_keyfile_path for run_locust.sh).
module "locust" {
  source                   = "./modules/locust_infrastructure"
  locustMasterInstanceType = var.locustMasterInstanceType
  locustWorkerInstanceType = var.locustWorkerInstanceType
  keyName                  = var.keyName
  awsSubnetId              = var.awsSubnetId
  awsVpcId                 = var.awsVpcId
  workernodeCount          = var.workernodeCount
  allowedIngressCidr       = var.allowedIngressCidr
}

module "lakebase" {
  source                 = "./modules/lakebase"
  lakebaseProjectName    = var.lakebaseProjectName
  lakebaseProjectId      = var.lakebaseProjectId
  lakebasePgVersion      = var.lakebasePgVersion
  lakebase_min_cu        = var.lakebase_min_cu
  lakebase_max_cu        = var.lakebase_max_cu
  lakebaseSuspendTimeout = var.lakebaseSuspendTimeout
}

module "databricks" {
  source                         = "./modules/databricks"
  locust_external_ips            = module.locust.locust_external_ips
  service_principal_display_name = var.databricks_service_principal_display_name
  ip_access_list_label           = var.databricks_ip_access_list_label
  enable_ip_access_list          = var.enable_ip_access_list
  lakebase_branch_name           = module.lakebase.branch_name

  depends_on = [module.locust, module.lakebase]
}
