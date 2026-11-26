# ==============================================================================
# ShopLite: Compute Module (Question 4.c)
# - 1 Kubernetes Control-Plane EC2 instance
# - 2 Kubernetes Worker EC2 instances in private subnets
# - Dedicated 10GB gp3 EBS volumes on workers for PostgreSQL & Observability PVCs
# - IAM Instance Profile with SSM, ECR ReadOnly, and EBS CSI Driver policies
# ==============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

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

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "aws_caller_identity" "current" {}

# Ephemeral S3 bucket used by Ansible amazon.aws.aws_ssm connection plugin (destroyed automatically on terraform destroy)
resource "aws_s3_bucket" "ssm_staging" {
  count         = var.enable_ssh_bastion ? 0 : 1
  bucket        = "shoplite-ssm-staging-${data.aws_caller_identity.current.account_id}-${var.environment}"
  force_destroy = true

  tags = {
    Name = "shoplite-ssm-staging-${var.environment}"
  }
}

resource "aws_s3_bucket_public_access_block" "ssm_staging" {
  count                   = var.enable_ssh_bastion ? 0 : 1
  bucket                  = aws_s3_bucket.ssm_staging[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role_policy" "ssm_staging_bucket" {
  count = var.enable_ssh_bastion ? 0 : 1
  name  = "shoplite-ssm-staging-s3-${var.environment}"
  role  = aws_iam_role.ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ssm_staging[0].arn,
          "${aws_s3_bucket.ssm_staging[0].arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "shoplite-instance-profile-${var.environment}"
  role = aws_iam_role.ssm_role.name
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.control_plane_instance_type
  subnet_id                   = var.enable_ssh_bastion && length(var.public_subnet_ids) > 0 ? var.public_subnet_ids[0] : var.private_subnet_ids[0]
  associate_public_ip_address = var.enable_ssh_bastion && length(var.public_subnet_ids) > 0 ? true : false
  vpc_security_group_ids = compact([
    var.nodes_security_group_id,
    var.enable_ssh_bastion ? var.bastion_security_group_id : ""
  ])
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  key_name             = var.enable_ssh_bastion && var.key_name != "" ? var.key_name : null

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

resource "aws_instance" "workers" {
  count                  = var.worker_node_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.nodes_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  key_name               = var.enable_ssh_bastion && var.key_name != "" ? var.key_name : null

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

# Dedicated 10GB gp3 AWS EBS Volume per worker for DB & Observability storage
resource "aws_ebs_volume" "worker_data" {
  count             = var.worker_node_count
  availability_zone = aws_instance.workers[count.index].availability_zone
  size              = var.storage_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "shoplite-worker-${count.index + 1}-data-${var.environment}"
    Role = "k8s-persistent-storage"
  }
}

resource "aws_volume_attachment" "worker_data" {
  count        = var.worker_node_count
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.worker_data[count.index].id
  instance_id  = aws_instance.workers[count.index].id
  force_detach = true
}
