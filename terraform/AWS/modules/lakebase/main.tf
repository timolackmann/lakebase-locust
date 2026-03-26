terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.110"
    }
  }

  required_version = ">= 1.14.6"
}

# Lakebase Autoscale: create a Postgres project with default endpoint settings for autoscaling.
# Requires Databricks provider with workspace auth (e.g. profile or host + token).
# Docs: https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/postgres_project
#
# After apply, create a branch and endpoint (via UI/CLI or databricks_postgres_branch /
# databricks_postgres_endpoint) and use project_id, branch_id, endpoint_id in config.json for Locust autoscale mode.

resource "databricks_postgres_project" "this" {
  project_id = var.lakebaseProjectId

  spec = {
    pg_version   = var.lakebasePgVersion
    display_name = var.lakebaseProjectName

    default_endpoint_settings = {
      autoscaling_limit_min_cu   = var.lakebaseEndpoint_min_cu
      autoscaling_limit_max_cu   = var.lakebaseEndpoint_max_cu
      suspend_timeout_duration   = var.lakebaseSuspendTimeout
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
