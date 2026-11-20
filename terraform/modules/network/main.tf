# ==============================================================================
# ShopLite: Network Module (Question 4.a & 4.b)
# - Custom VPC spanning two Availability Zones
# - 2 Public Subnets & 2 Private Subnets
# - Internet Gateway & NAT Gateway with Route Tables
# - Least-Privilege Security Groups
# ==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# 1. Custom VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "shoplite-vpc-${var.environment}"
  }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "shoplite-igw-${var.environment}"
  }
}

# 3. Public Subnets (across 2 AZs)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "shoplite-public-subnet-${count.index + 1}-${var.environment}"
    "kubernetes.io/role/elb" = "1"
  }
}

# 4. Private Subnets (across 2 AZs)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                              = "shoplite-private-subnet-${count.index + 1}-${var.environment}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# 5. Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "shoplite-nat-eip-${var.environment}"
  }
}

# 6. NAT Gateway (placed in 1st public subnet)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "shoplite-nat-gw-${var.environment}"
  }
  depends_on = [aws_internet_gateway.igw]
}

# 7. Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "shoplite-public-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 8. Route Table for Private Subnets (via NAT Gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "shoplite-private-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ==============================================================================
# Security Groups (Question 4.b)
# ==============================================================================

# ALB Security Group (Public Ingress on 80 and 443)
resource "aws_security_group" "alb" {
  name        = "shoplite-alb-sg-${var.environment}"
  description = "Security Group for public Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow inbound HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow inbound HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "shoplite-alb-sg-${var.environment}"
  }
}

# Kubernetes Nodes Security Group (Private: NOT reachable directly from internet)
resource "aws_security_group" "nodes" {
  name        = "shoplite-nodes-sg-${var.environment}"
  description = "Security Group for Kubernetes control-plane and worker nodes"
  vpc_id      = aws_vpc.main.id

  # Ingress strictly from ALB to NodePort / Ingress controller port (e.g. 80, 443, 30000-32767)
  ingress {
    description     = "Allow traffic from ALB into Kubernetes Ingress"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Allow NodePort traffic from ALB"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Intra-cluster inter-node communication
  ingress {
    description = "Allow all intra-cluster traffic between nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "shoplite-nodes-sg-${var.environment}"
  }
}

