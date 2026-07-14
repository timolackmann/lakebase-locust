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

module "eks" {
  source            = "./modules/eks_infrastructure"
  awsVpcId          = var.awsVpcId
  privateSubnetIds  = var.privateSubnetIds
  clusterName       = var.clusterName
  kubernetesVersion = var.kubernetesVersion
  nodeInstanceType  = var.nodeInstanceType
  workerReplicas    = var.workerReplicas
  ecrRepositoryName = var.ecrRepositoryName
}

module "lakebase" {
  source                 = "../../modules/lakebase"
  lakebaseProjectName    = var.lakebaseProjectName
  lakebaseProjectId      = var.lakebaseProjectId
  lakebasePgVersion      = var.lakebasePgVersion
  lakebase_min_cu        = var.lakebase_min_cu
  lakebase_max_cu        = var.lakebase_max_cu
  lakebaseSuspendTimeout = var.lakebaseSuspendTimeout
}

module "databricks" {
  source                         = "../../modules/databricks"
  locust_external_ips            = module.eks.egress_ips
  service_principal_display_name = var.databricks_service_principal_display_name
  ip_access_list_label           = var.databricks_ip_access_list_label
  enable_ip_access_list          = var.enable_ip_access_list
  lakebase_branch_name           = module.lakebase.branch_name

  depends_on = [module.eks, module.lakebase]
}
