output "region" {
  value = var.region
}

output "aws_profile" {
  value = var.awsProfile
}

output "ecr_repository_url" {
  value = module.eks.ecr_repository_url
}

output "locust_image" {
  description = "Full image reference for Locust pods (repository:tag)"
  value       = "${module.eks.ecr_repository_url}:${var.imageTag}"
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "worker_replicas" {
  value = module.eks.worker_replicas
}

output "image_tag" {
  value = var.imageTag
}

output "lakebase_project_id" {
  value = module.lakebase.project_id
}

output "lakebase_project_name" {
  value = module.lakebase.project_name
}

output "lakebase_project_status" {
  value     = module.lakebase.project_status
  sensitive = true
}

output "lakebase_project_uid" {
  value = module.lakebase.uid
}

output "lakebase_branch_id" {
  value = module.lakebase.branch_id
}

output "lakebase_endpoint_id" {
  value = module.lakebase.endpoint_id
}

output "databricks_service_principal_id" {
  value = module.databricks.service_principal_id
}

output "databricks_ip_access_list_id" {
  value = module.databricks.ip_access_list_id
}

output "service_principal_secret" {
  description = "Secret of the Databricks service principal (use: terraform output -raw service_principal_secret)"
  value       = module.databricks.service_principal_secret
  sensitive   = true
}

output "egress_ips" {
  description = "NAT gateway egress IPs used for the Databricks IP access list"
  value       = module.eks.egress_ips
}
