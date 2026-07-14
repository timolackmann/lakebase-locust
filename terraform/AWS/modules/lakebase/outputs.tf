output "project_id" {
  description = "Lakebase project ID (use in config.json lakebase.project_id)"
  value       = databricks_postgres_project.this.project_id
}

output "project_name" {
  description = "Lakebase project full resource name (projects/<project_id>)"
  value       = databricks_postgres_project.this.name
}

output "project_status" {
  description = "Lakebase project status"
  value       = try(databricks_postgres_project.this.status, null)
  sensitive   = true
}

output "uid" {
  description = "Lakebase project UID"
  value       = databricks_postgres_project.this.uid
}

output "branch_id" {
  description = "Lakebase branch ID (use in config.json lakebase.branch_id)"
  value       = databricks_postgres_branch.load_test_branch.branch_id
}

output "branch_name" {
  description = "Lakebase branch full resource name (projects/<project_id>/branches/<branch_id>)"
  value       = databricks_postgres_branch.load_test_branch.name
}

output "endpoint_id" {
  description = "Lakebase endpoint ID (use in config.json lakebase.endpoint_id)"
  value       = databricks_postgres_endpoint.primary.endpoint_id
}
