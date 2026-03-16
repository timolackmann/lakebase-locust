variable "locust_external_ips" {
  type        = list(string)
  description = "External IP addresses of Locust nodes (CIDR format, e.g. x.x.x.x/32) to allow in the IP access list"
}

variable "enable_ip_access_list" {
  type        = bool
  description = "Whether to create the IP access list for Locust IPs. Use a plan-time known value so count does not depend on resource attributes (e.g. from module.locust)."
  default     = true
}

variable "service_principal_display_name" {
  type        = string
  description = "Display name for the Databricks service principal"
  default     = "locust-tester-sp"
}

variable "ip_access_list_label" {
  type        = string
  description = "Label for the IP access list containing Locust IPs"
  default     = "locust-load-test-allow"
}
