# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Variables
variable "cluster_name" {
  description = "Name of the ROSA cluster"
  type        = string
  default     = "sapeic"
}

variable "region" {
  description = "AWS region for the cluster"
  type        = string
  default     = "us-east-1"
}

variable "rosa_version" {
  description = "ROSA version to deploy"
  type        = string
  default     = "4.15.35"
}

variable "deploy_postgres" {
  description = "Whether to deploy RDS PostgreSQL"
  type        = bool
  default     = true
}

variable "deploy_redis" {
  description = "Whether to deploy ElastiCache Redis"
  type        = bool
  default     = true
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# VPC and networking
resource "aws_vpc" "rosa_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.rosa_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.rosa_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "rosa_igw" {
  vpc_id = aws_vpc.rosa_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.rosa_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rosa_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security groups
resource "aws_security_group" "rosa_cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = aws_vpc.rosa_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

# RDS PostgreSQL (if enabled)
resource "aws_db_subnet_group" "postgres" {
  count      = var.deploy_postgres ? 1 : 0
  name       = "${var.cluster_name}-postgres-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.cluster_name}-postgres-subnet-group"
  }
}

resource "aws_security_group" "postgres" {
  count       = var.deploy_postgres ? 1 : 0
  name_prefix = "${var.cluster_name}-postgres-"
  vpc_id      = aws_vpc.rosa_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rosa_cluster.id]
  }

  tags = {
    Name = "${var.cluster_name}-postgres-sg"
  }
}

resource "aws_db_instance" "postgres" {
  count               = var.deploy_postgres ? 1 : 0
  identifier          = "${var.cluster_name}-postgres"
  engine              = "postgres"
  engine_version      = "15.4"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  storage_type        = "gp2"
  storage_encrypted   = true
  
  db_name  = "sapeic"
  username = "postgres"
  password = var.postgres_admin_password
  
  vpc_security_group_ids = [aws_security_group.postgres[0].id]
  db_subnet_group_name   = aws_db_subnet_group.postgres[0].name
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = true
  
  tags = {
    Name = "${var.cluster_name}-postgres"
  }
}

# ElastiCache Redis (if enabled)
resource "aws_elasticache_subnet_group" "redis" {
  count      = var.deploy_redis ? 1 : 0
  name       = "${var.cluster_name}-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_security_group" "redis" {
  count       = var.deploy_redis ? 1 : 0
  name_prefix = "${var.cluster_name}-redis-"
  vpc_id      = aws_vpc.rosa_vpc.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.rosa_cluster.id]
  }

  tags = {
    Name = "${var.cluster_name}-redis-sg"
  }
}

resource "aws_elasticache_cluster" "redis" {
  count                = var.deploy_redis ? 1 : 0
  cluster_id           = "${var.cluster_name}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  security_group_ids   = [aws_security_group.redis[0].id]
  subnet_group_name    = aws_elasticache_subnet_group.redis[0].name
  
  tags = {
    Name = "${var.cluster_name}-redis"
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.rosa_vpc.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "postgres_endpoint" {
  description = "PostgreSQL endpoint"
  value       = var.deploy_postgres ? aws_db_instance.postgres[0].endpoint : null
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string"
  value       = var.deploy_postgres ? "postgresql://postgres:${var.postgres_admin_password}@${aws_db_instance.postgres[0].endpoint}/${aws_db_instance.postgres[0].db_name}" : null
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = var.deploy_redis ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : null
}

output "redis_port" {
  description = "Redis port"
  value       = var.deploy_redis ? aws_elasticache_cluster.redis[0].port : null
} 