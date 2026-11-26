output "aws_account_id" {
  description = "Active AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

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

output "control_plane_id" {
  description = "EC2 Instance ID of K8s Control Plane (for AWS SSM StartSession)"
  value       = module.compute.control_plane_id
}

output "control_plane_public_ip" {
  description = "Public IP of K8s Control Plane instance (null when enable_ssh_bastion is false)"
  value       = var.enable_ssh_bastion ? module.compute.control_plane_public_ip : null
}

output "worker_private_ips" {
  description = "Private IPs of K8s Worker nodes"
  value       = module.compute.worker_private_ips
}

output "worker_ebs_volume_ids" {
  description = "Dedicated 10GB gp3 EBS volume IDs attached to worker nodes"
  value       = module.compute.worker_ebs_volume_ids
}

output "ecr_registry_url" {
  description = "ECR Registry base URL"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_repository_urls" {
  description = "ECR Repository URLs for docker push"
  value       = module.ecr.repository_urls
}
