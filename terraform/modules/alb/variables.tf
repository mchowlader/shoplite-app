variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB is deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "worker_ids" {
  description = "List of worker EC2 instance IDs to attach to target group"
  type        = list(string)
  default     = []
}
