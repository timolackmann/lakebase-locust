variable "awsVpcId" {
  type        = string
  description = "VPC ID where the EKS cluster runs (used to discover NAT gateway egress IPs)"
}

variable "privateSubnetIds" {
  type        = list(string)
  description = "Private subnet IDs for the EKS cluster and node group (at least two AZs recommended)"
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
  description = "Desired number of Locust worker pod replicas (also sets node group desired size)"
  default     = 3
}

variable "ecrRepositoryName" {
  type        = string
  description = "ECR repository name for the Locust container image"
  default     = "locust-lakebase"
}
