variable "region" {
  type        = string
  description = "AWS Region"
}

variable "awsProfile" {
  type = string
  description = "aws profile for EC2 creation"
}

variable "locustMasterInstanceType" {
  type        = string
  description = "AWS Instance Type of the locust master"
  default     = "t2.small"
}

variable "locustWorkerInstanceType" {
  type        = string
  description = "AWS Instance Type of the locust workers"
  default     = "t2.small"
}

variable "workernodeCount" {
  type        = number
  description = "Amount of worker nodes to be deployed"
  default     = 1
}

variable "workersPerNode" {
  type        = number
  default     = 2
  description = "Amount of users to be created for each worker"
}

variable "keyName" {
  type        = string
  description = "Name of your AWS key"
}

variable "keyPath" {
  type        = string
  description = "Full path to your AWS key"
}

variable "awsVpcId" {
  type        = string
  description = "ID of the VPC on AWS used for the private endpoint and locust nodes"
}

variable "awsSubnetId" {
  type        = string
  description = "ID of the subnet on AWS used for the private endpoint and locust nodes"
}

variable "allowedIngressCidr" {
  type        = string
  description = "CIDR (e.g. your IP as x.x.x.x/32) allowed for SSH and Locust web UI (port 8089)"
}

variable "locustFiles" {
  type        = list(string)
  description = "Locust related files to be copied to locust master and workers"
  default     = ["locust.py", "lakebase_user.py", "config.json"]
}

variable "locustExecuteFile" {
  type        = string
  description = "Locust file for execution"
  default     = "locust.py"
}

variable "databricksProfile" {
  type        = string
  description = "Databricks CLI profile"
}

variable "databricks_service_principal_display_name" {
  type        = string
  description = "Display name for the Databricks service principal created for Locust"
  default     = "locust-tester-sp"
}

variable "databricks_ip_access_list_label" {
  type        = string
  description = "Label for the IP access list containing Locust external IPs"
  default     = "locust-load-test-allow"
}

variable "lakebaseProjectName" {
  type        = string
  description = "Lakebase project name"
}

variable "LakebaseProjectId" {
  type        = string
  description = "Lakebase project ID"
}

variable "lakebasePgVersion" {
  type        = number
  description = "Lakebase PostgreSQL version"
  default     = 17
}

variable "lakebaseEndpoint_min_cu" {
  type        = number
  description = "Lakebase endpoint minimum CU"
}

variable "lakebaseEndpoint_max_cu" {
  type        = number
  description = "Lakebase endpoint maximum CU"
}

variable "lakebaseSuspendTimeout" {
  type        = string
  description = "Lakebase endpoint suspend timeout"
  default     = "300s"
}

# --- Grant service principal to Lakebase Postgres (OAuth) ---
# After creating a branch and endpoint (in UI or via CLI), set these so Terraform can run the grant script.

variable "lakebase_branch_id" {
  type        = string
  description = "Lakebase branch ID (from UI/CLI after creating a branch). Required when run_grant_sp_to_lakebase is true."
  default     = ""
}

variable "lakebase_endpoint_id" {
  type        = string
  description = "Lakebase endpoint ID (from UI/CLI after creating an endpoint). Required when run_grant_sp_to_lakebase is true."
  default     = ""
}

variable "run_grant_sp_to_lakebase" {
  type        = bool
  description = "If true, run SQL on Lakebase Postgres to grant the Terraform-created service principal OAuth access (requires lakebase_branch_id and lakebase_endpoint_id)."
  default     = false
}

variable "lakebase_database" {
  type        = string
  description = "Lakebase Postgres database name used when granting the service principal (default: databricks_postgres)."
  default     = "databricks_postgres"
}