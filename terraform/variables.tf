variable "aws_region" {
  description = "AWS deployment region (Singapore for Poridhi Lab)"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the 2 public subnets across 2 AZs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the 2 private subnets across 2 AZs"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for K8s control plane node"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for K8s worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_node_count" {
  description = "Number of worker nodes in private subnets"
  type        = number
  default     = 2
}

variable "storage_volume_size_gb" {
  description = "Dedicated AWS gp3 EBS volume size (GB) attached to each worker for DB and observability PVCs"
  type        = number
  default     = 10
}

variable "enable_ssh_bastion" {
  description = "Enable SSH bastion on control plane when AWS SSM is blocked by sandbox SCP"
  type        = bool
  default     = false
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH bastion ingress when enable_ssh_bastion is true"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH administration access"
  type        = string
  default     = "shoplite-key"
}

variable "ssh_private_key_path" {
  description = "Local path to SSH private key written into generated Ansible inventory"
  type        = string
  default     = "~/.ssh/shoplite-key.pem"
}

variable "generate_ansible_inventory" {
  description = "Automatically generate ../ansible/inventory/hosts.ini from Terraform outputs"
  type        = bool
  default     = true
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD (Cost Guard requirement)"
  type        = string
  default     = "20"
}

variable "alert_email" {
  description = "Email address for AWS Budget alarm notifications"
  type        = string
  default     = "admin@example.com"
}
