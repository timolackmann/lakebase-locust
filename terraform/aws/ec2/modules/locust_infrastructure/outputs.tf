output "master_public_dns" {
  description = "Locust master public dns"
  value       = aws_instance.locust_main.public_dns
}

output "workerNodes_public_dns" {
  description = "List of locust worker public dns"
  value       = aws_instance.locust_worker[*].public_dns
}

output "workerNodes_private_ips" {
  description = "List of locust worker private ips"
  value       = aws_instance.locust_worker[*].private_ip
}

output "master_public_ip" {
  description = "Locust master public (external) IP for Databricks IP access list"
  value       = aws_instance.locust_main.public_ip
}

output "worker_public_ips" {
  description = "List of locust worker public (external) IPs for Databricks IP access list"
  value       = aws_instance.locust_worker[*].public_ip
}

output "locust_external_ips" {
  description = "All Locust node external IPs (master + workers) as /32 CIDRs for IP access lists"
  value       = [for ip in compact(concat([aws_instance.locust_main.public_ip], aws_instance.locust_worker[*].public_ip)) : "${ip}/32"]
}
