# ==============================================================================
# ShopLite: Application Load Balancer Module (Question 4.d)
# - Public Internet-Facing ALB in Public Subnets across 2 AZs
# - HTTP Listener on port 80 forwarding to K8s Ingress Target Group
# ==============================================================================

resource "aws_lb" "main" {
  name               = "shoplite-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "shoplite-alb-${var.environment}"
  }
}

resource "aws_lb_target_group" "k8s_ingress" {
  name        = "shoplite-ingress-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }

  tags = {
    Name = "shoplite-ingress-tg-${var.environment}"
  }
}

# Attach worker instances to Target Group
resource "aws_lb_target_group_attachment" "workers" {
  count            = length(var.worker_ids)
  target_group_arn = aws_lb_target_group.k8s_ingress.arn
  target_id        = var.worker_ids[count.index]
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_ingress.arn
  }
}

