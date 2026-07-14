output "ecr_repository_url" {
  description = "ECR repository URL (without tag)"
  value       = aws_ecr_repository.locust.repository_url
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "worker_replicas" {
  description = "Default Locust worker Deployment replica count"
  value       = var.workerReplicas
}

output "egress_ips" {
  description = "NAT gateway Elastic IPs in the VPC as /32 CIDRs for Databricks IP access lists"
  value = [
    for ngw in data.aws_nat_gateway.each : "${ngw.public_ip}/32"
    if ngw.public_ip != null && ngw.public_ip != ""
  ]
}
