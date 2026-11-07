output "vpc_id" {
  description = "Custom VPC ID"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs (across 2 AZs)"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private Subnet IDs (across 2 AZs)"
  value       = module.network.private_subnet_ids
}

output "alb_dns_name" {
  description = "Public URL of Application Load Balancer"
  value       = "http://${module.alb.alb_dns_name}"
}

output "control_plane_private_ip" {
  description = "Private IP of K8s Control Plane instance"
  value       = module.compute.control_plane_private_ip
}

output "worker_private_ips" {
  description = "Private IPs of K8s Worker nodes"
  value       = module.compute.worker_private_ips
}

output "ecr_repository_urls" {
  description = "ECR Repository URLs for docker push"
  value       = module.ecr.repository_urls
}
