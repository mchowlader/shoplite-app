# ==============================================================================
# ShopLite: Compute Module (Question 4.c)
# - 1 Kubernetes Control-Plane EC2 instance in private subnet
# - 2 Kubernetes Worker EC2 instances in private subnet
# - AWS Systems Manager (SSM) Session Manager administrative access
# - Encrypted GP3 Root EBS volumes
# ==============================================================================

# 1. Lookup Latest Official Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 2. IAM Role & Instance Profile for AWS Systems Manager (SSM)
resource "aws_iam_role" "ssm_role" {
  name = "shoplite-ssm-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "shoplite-instance-profile-${var.environment}"
  role = aws_iam_role.ssm_role.name
}

# 3. Control-Plane Node (Private Subnet 1)
resource "aws_instance" "control_plane" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.control_plane_instance_type
  subnet_id            = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.nodes_security_group_id]
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  key_name             = var.key_name != "" ? var.key_name : null

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "shoplite-k8s-control-plane-${var.environment}"
    Role = "control-plane"
  }
}

# 4. Worker Nodes (Distributed across Private Subnets)
resource "aws_instance" "workers" {
  count                = var.worker_node_count
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.worker_instance_type
  subnet_id            = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.nodes_security_group_id]
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  key_name             = var.key_name != "" ? var.key_name : null

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "shoplite-k8s-worker-${count.index + 1}-${var.environment}"
    Role = "worker"
  }
}
