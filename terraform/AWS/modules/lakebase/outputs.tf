output "project_id" {
  description = "Lakebase project ID (use in config.json lakebase.project_id for autoscale mode)"
  value       = databricks_postgres_project.this.project_id
}

output "project_name" {
  description = "Lakebase project full resource name (projects/<project_id>)"
  value       = databricks_postgres_project.this.name
}

# Status may contain branch and endpoint info after default branch/endpoint exist.
# Use these in config.json for Locust autoscale mode: project_id, branch_id, endpoint_id.
output "project_status" {
  description = "Lakebase project status (may include branch and endpoint info)"
  value       = try(databricks_postgres_project.this.status, null)
  sensitive   = true
}

output "uid" {
  description = "Lakebase project UID"
  value       = databricks_postgres_project.this.uid
}

output "branch_id" {
  description = "Lakebase branch ID"
  value       = databricks_postgres_branch.load_test_branch.branch_id
}