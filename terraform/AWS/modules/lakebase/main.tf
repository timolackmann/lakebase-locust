terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
    }
  }
}

# Lakebase autoscale: Postgres project, branch, and primary read-write endpoint.
# Docs: https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/postgres_project

resource "databricks_postgres_project" "this" {
  project_id = var.lakebaseProjectId

  spec = {
    pg_version   = var.lakebasePgVersion
    display_name = var.lakebaseProjectName

    default_endpoint_settings = {
      autoscaling_limit_min_cu = var.lakebase_min_cu
      autoscaling_limit_max_cu = var.lakebase_max_cu
      suspend_timeout_duration = var.lakebaseSuspendTimeout
    }
  }
}

resource "databricks_postgres_branch" "load_test_branch" {
  branch_id = "br-load-testing"
  parent    = databricks_postgres_project.this.name
  spec = {
    no_expiry = true
  }
}

resource "databricks_postgres_endpoint" "primary" {
  endpoint_id      = "primary"
  parent           = databricks_postgres_branch.load_test_branch.name
  replace_existing = true
  spec = {
    endpoint_type = "ENDPOINT_TYPE_READ_WRITE"
  }
}
