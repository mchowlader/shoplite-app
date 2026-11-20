# ==============================================================================
# ShopLite: Root Terraform Orchestrator (Question 4: AWS Infrastructure as Code)
# Assembles 4 Reusable Modules: network, compute, alb, ecr
# Cost Guard: Project Tagging & USD 20 Budget Alarm
# Region: Singapore (ap-southeast-1)
# ==============================================================================

# 1. Modular VPC & Least-Privilege Security Groups
module "network" {
  source = "./modules/network"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  environment          = var.environment
}

# 2. Compute: 1 Control-Plane + 2 Worker EC2 Nodes in Private Subnets
module "compute" {
  source = "./modules/compute"

  environment                 = var.environment
  private_subnet_ids          = module.network.private_subnet_ids
  nodes_security_group_id     = module.network.nodes_security_group_id
  control_plane_instance_type = var.control_plane_instance_type
  worker_instance_type        = var.worker_instance_type
  worker_node_count           = var.worker_node_count
  key_name                    = var.key_name
}

# 3. Application Load Balancer in Public Subnets
module "alb" {
  source = "./modules/alb"

  environment           = var.environment
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  worker_ids            = module.compute.worker_ids
}

# 4. Amazon ECR Repositories for all 3 microservices
module "ecr" {
  source = "./modules/ecr"

  environment = var.environment
}

# ==============================================================================
# Cost Guard: AWS Budget Alarm at USD 20 (Question 4 Cost Guard requirement)
# ==============================================================================
resource "aws_budgets_budget" "cost_guard" {
  name              = "shoplite-monthly-budget-${var.environment}"
  budget_type       = "COST"
  limit_amount      = var.budget_limit_usd
  limit_unit        = "USD"
  time_period_start = "2026-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

