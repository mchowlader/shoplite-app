variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_ssh_bastion" {
  description = "Whether to allow inbound SSH on control-plane bastion SG (fallback when SSM is blocked)"
  type        = bool
  default     = false
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed for SSH bastion ingress"
  type        = string
  default     = "0.0.0.0/0"
}
