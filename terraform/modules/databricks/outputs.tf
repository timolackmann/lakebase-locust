output "service_principal_id" {
  description = "Application ID of the created Databricks service principal"
  value       = databricks_service_principal.locust-sp.application_id
}

output "service_principal_display_name" {
  description = "Display name of the service principal"
  value       = databricks_service_principal.locust-sp.display_name
}

output "ip_access_list_id" {
  description = "ID of the IP access list containing Locust external IPs (null if no Locust IPs)"
  value       = var.enable_ip_access_list ? databricks_ip_access_list.locust-ip-access-list[0].id : null
}

output "service_principal_secret" {
  description = "Secret of the service principal"
  value       = databricks_service_principal_secret.locust-sp-secret.secret
}