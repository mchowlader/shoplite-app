variable "environment" {
  description = "Environment name"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for worker and control plane nodes"
  type        = list(string)
}

variable "nodes_security_group_id" {
  description = "Security Group ID for K8s nodes"
  type        = string
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

variable "key_name" {
  description = "Optional Key Pair name for SSH"
  type        = string
  default     = ""
}
