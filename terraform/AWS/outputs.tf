output "locust_UI" {
  value = module.locust.master_public_dns
}

output "worker_per_node" {
  value = var.workersPerNode
}

output "locust_master_dns" {
  value = module.locust.master_public_dns
}

output "locust_workernodes_dns" {
  value = module.locust.workerNodes_public_dns
}

output "locust_workernodes_private_ips" {
  value = module.locust.workerNodes_private_ips
}

output "ssh_keyfile_path" {
  value = var.keyPath
}

output "locust_files" {
  value = join(",", var.locustFiles)
}

output "locust_execution_file" {
  value = var.locustExecuteFile
}

# Lakebase autoscale project (use project_id, branch_id, endpoint_id in config.json for Locust autoscale mode)
output "lakebase_project_id" {
  value = module.lakebase.project_id
}

output "lakebase_project_name" {
  value = module.lakebase.project_name
}

output "lakebase_project_status" {
  value = module.lakebase.project_status
  sensitive = true
}

output "lakebase_project_uid" {
  value = module.lakebase.uid
}

output "lakebase_branch_id" {
  value = module.lakebase.branch_id
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
