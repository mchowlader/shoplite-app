output "control_plane_id" {
  description = "ID of the control plane EC2 instance"
  value       = aws_instance.control_plane.id
}

output "control_plane_private_ip" {
  description = "Private IP address of the control plane node"
  value       = aws_instance.control_plane.private_ip
}

output "control_plane_public_ip" {
  description = "Public IP address of the control plane node (only when enable_ssh_bastion is true)"
  value       = var.enable_ssh_bastion ? aws_instance.control_plane.public_ip : null
}

output "worker_ids" {
  description = "List of worker EC2 instance IDs"
  value       = aws_instance.workers[*].id
}

output "worker_private_ips" {
  description = "List of private IP addresses of the worker nodes"
  value       = aws_instance.workers[*].private_ip
}

output "worker_ebs_volume_ids" {
  description = "List of dedicated EBS volume IDs attached to worker nodes"
  value       = aws_ebs_volume.worker_data[*].id
}

output "ssm_staging_bucket_name" {
  description = "Ephemeral S3 staging bucket for Ansible AWS SSM file transfers (empty when enable_ssh_bastion is true)"
  value       = var.enable_ssh_bastion ? "" : aws_s3_bucket.ssm_staging[0].id
}
