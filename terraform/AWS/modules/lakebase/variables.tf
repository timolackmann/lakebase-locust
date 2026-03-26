variable "lakebaseProjectName" {
  type        = string
  description = "Lakebase project name"
}

variable "lakebaseProjectId" {
  type        = string
  description = "Lakebase project ID (used as project identifier in Databricks)"
}

variable "lakebasePgVersion" {
  type        = number
  description = "Lakebase PostgreSQL version"
  default     = 17
}

variable "lakebaseEndpoint_min_cu" {
  type        = number
  description = "Lakebase autoscale endpoint minimum compute units (e.g. 0.5, 1, 2)"
}

variable "lakebaseEndpoint_max_cu" {
  type        = number
  description = "Lakebase autoscale endpoint maximum compute units (e.g. 4, 8, 16)"
}

variable "lakebaseSuspendTimeout" {
  type        = string
  description = "Lakebase endpoint suspend timeout duration (e.g. 300s)"
  default     = "300s"
}
