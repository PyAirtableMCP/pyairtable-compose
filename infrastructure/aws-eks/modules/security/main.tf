# Security Module for PyAirtable EKS Infrastructure
# Security groups and network access control

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  name = "${var.project_name}-${var.environment}"
}

# EKS Cluster Security Group
resource "aws_security_group" "cluster" {
  name        = "${local.name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  # Allow HTTPS traffic from nodes
  ingress {
    description = "HTTPS from worker nodes"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = true
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-cluster-sg"
    Type = "EKS-Cluster"
  })
}

# EKS Node Group Security Group
resource "aws_security_group" "node" {
  name        = "${local.name}-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Allow nodes to communicate with each other
  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Allow pods to communicate with the cluster API Server
  ingress {
    description     = "Pod to cluster API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  # Allow kubelet and pod communication
  ingress {
    description     = "Kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  # Allow NodePort services
  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow SSH access (restrict in production)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.environment == "production" ? [] : [var.vpc_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-node-sg"
    Type = "EKS-Node"
  })
}

# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # Allow HTTP traffic
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS traffic
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-alb-sg"
    Type = "ALB"
  })
}

# Database Security Group
resource "aws_security_group" "database" {
  name        = "${local.name}-db-sg"
  description = "Security group for database access"
  vpc_id      = var.vpc_id

  # PostgreSQL access from nodes
  ingress {
    description     = "PostgreSQL from nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.node.id]
  }

  # Redis access from nodes
  ingress {
    description     = "Redis from nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.node.id]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-db-sg"
    Type = "Database"
  })
}

# EFS Security Group
resource "aws_security_group" "efs" {
  name        = "${local.name}-efs-sg"
  description = "Security group for EFS access"
  vpc_id      = var.vpc_id

  # NFS access from nodes
  ingress {
    description     = "NFS from nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.node.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-efs-sg"
    Type = "EFS"
  })
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Security group for RDS database"
  vpc_id      = var.vpc_id

  # PostgreSQL access from nodes
  ingress {
    description     = "PostgreSQL from nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.node.id]
  }

  # Allow access from bastion host (if needed)
  dynamic "ingress" {
    for_each = var.enable_bastion ? [1] : []
    content {
      description     = "PostgreSQL from bastion"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [aws_security_group.bastion[0].id]
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name}-rds-sg"
    Type = "RDS"
  })
}

# ElastiCache Security Group
resource "aws_security_group" "elasticache" {
  name        = "${local.name}-elasticache-sg"
  description = "Security group for ElastiCache"
  vpc_id      = var.vpc_id

  # Redis access from nodes
  ingress {
    description     = "Redis from nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.node.id]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-elasticache-sg"
    Type = "ElastiCache"
  })
}

# Bastion Host Security Group (optional, for debugging)
resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name        = "${local.name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  # SSH access (restrict source IPs in production)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidrs
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-bastion-sg"
    Type = "Bastion"
  })
}

# Network ACL for additional security layer
resource "aws_network_acl" "private" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Allow inbound HTTP/HTTPS
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow inbound SSH from VPC
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }

  # Allow inbound ephemeral ports
  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, {
    Name = "${local.name}-private-nacl"
    Type = "Private-NACL"
  })
}

# Security Group Rules for cluster to node communication
resource "aws_security_group_rule" "cluster_to_node" {
  description              = "Allow cluster to communicate with nodes"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_to_cluster" {
  description              = "Allow nodes to communicate with cluster"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
  type                     = "ingress"
}