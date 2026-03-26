terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.110"
    }
  }

  required_version = ">= 1.14.6"
}
# Databricks module: service principal and IP access list for Locust load testing.
# Requires Databricks provider with workspace auth (e.g. profile or host + token).

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
