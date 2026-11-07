output "control_plane_id" {
  description = "ID of the control plane EC2 instance"
  value       = aws_instance.control_plane.id
}

output "control_plane_private_ip" {
  description = "Private IP address of the control plane node"
  value       = aws_instance.control_plane.private_ip
}

output "worker_ids" {
  description = "List of worker EC2 instance IDs"
  value       = aws_instance.workers[*].id
}

output "worker_private_ips" {
  description = "List of private IP addresses of the worker nodes"
  value       = aws_instance.workers[*].private_ip
}
