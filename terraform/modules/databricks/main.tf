terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
    }
  }
}

# Databricks module: service principal, IP access list, and Lakebase Postgres role for Locust.

resource "databricks_service_principal" "locust-sp" {
  display_name = var.service_principal_display_name
}

resource "databricks_ip_access_list" "locust-ip-access-list" {
  count        = var.enable_ip_access_list ? 1 : 0
  label        = var.ip_access_list_label
  list_type    = "ALLOW"
  ip_addresses = var.locust_external_ips
}

resource "databricks_service_principal_secret" "locust-sp-secret" {
  service_principal_id = databricks_service_principal.locust-sp.id
}

resource "databricks_postgres_role" "locust_sp" {
  role_id = "locust-sp"
  parent  = var.lakebase_branch_name
  spec = {
    identity_type    = "SERVICE_PRINCIPAL"
    postgres_role    = databricks_service_principal.locust-sp.application_id
    auth_method      = "LAKEBASE_OAUTH_V1"
    membership_roles = ["DATABRICKS_SUPERUSER"]
  }
}
