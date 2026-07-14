variable "region" {
  type        = string
  description = "AWS region for EKS and related resources"
}

variable "awsProfile" {
  type        = string
  description = "AWS CLI named profile for Terraform/provider authentication"
}

variable "awsVpcId" {
  type        = string
  description = "Existing VPC ID (must have NAT gateways for Databricks egress IP allow lists)"
}

variable "privateSubnetIds" {
  type        = list(string)
  description = "Private subnet IDs for the EKS cluster and node group (tagged for EKS)"
}

variable "clusterName" {
  type        = string
  description = "EKS cluster name"
  default     = "locust-eks"
}

variable "kubernetesVersion" {
  type        = string
  description = "Kubernetes version for the EKS control plane"
  default     = "1.29"
}

variable "nodeInstanceType" {
  type        = string
  description = "EC2 instance type for EKS worker nodes"
  default     = "m5.large"
}

variable "workerReplicas" {
  type        = number
  description = "Locust worker Deployment replicas (also sets node group desired size)"
  default     = 3
}

variable "ecrRepositoryName" {
  type        = string
  description = "ECR repository name for the Locust container image"
  default     = "locust-lakebase"
}

variable "imageTag" {
  type        = string
  description = "Docker image tag pushed by deploy_locust.sh"
  default     = "latest"
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
  description = "Label for the IP access list containing cluster egress IPs"
  default     = "locust-load-test-allow"
}

variable "lakebaseProjectName" {
  type        = string
  description = "Lakebase project name"
}

variable "lakebaseProjectId" {
  type        = string
  description = "Lakebase project ID"
}

variable "lakebasePgVersion" {
  type        = number
  description = "Lakebase PostgreSQL version"
  default     = 17
}

variable "lakebase_min_cu" {
  type        = number
  description = "Lakebase endpoint minimum CU"
}

variable "lakebase_max_cu" {
  type        = number
  description = "Lakebase endpoint maximum CU"
}

variable "lakebaseSuspendTimeout" {
  type        = string
  description = "Lakebase endpoint suspend timeout"
  default     = "300s"
}

variable "enable_ip_access_list" {
  type        = bool
  description = "Whether to create the IP access list for NAT gateway egress IPs. Set to true and apply again after NAT gateways are discoverable."
  default     = false
}
