variable "environment" {
  description = "Environment name"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for worker and control plane nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Optional list of public subnet IDs (used when enable_ssh_bastion is true)"
  type        = list(string)
  default     = []
}

variable "nodes_security_group_id" {
  description = "Security Group ID for K8s nodes"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Conditional Bastion Security Group ID attached only to control-plane when enable_ssh_bastion is true"
  type        = string
  default     = ""
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for control plane"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for workers"
  type        = string
  default     = "t3.medium"
}

variable "worker_node_count" {
  description = "Number of worker nodes to provision"
  type        = number
  default     = 2
}

variable "storage_volume_size_gb" {
  description = "Size in GB of dedicated gp3 EBS volume attached to each worker for DB and observability PVCs"
  type        = number
  default     = 10
}

variable "key_name" {
  description = "Optional Key Pair name for SSH"
  type        = string
  default     = ""
}

variable "enable_ssh_bastion" {
  description = "Whether to deploy control-plane with public bastion SSH access"
  type        = bool
  default     = false
}
