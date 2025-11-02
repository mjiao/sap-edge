# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

###########################################
# Security Groups
###########################################

#checkov:skip=CKV_AWS_382:Outbound internet access required for testing environment
resource "aws_security_group" "postgres" {
  count       = var.deploy_postgres ? 1 : 0
  name        = "${var.cluster_name}-postgres-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc[0].vpc_id

  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.postgres_allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    #tfsec:ignore:aws-ec2-no-public-egress-sgr Outbound internet access required for testing environment
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-postgres-sg"
      Service = "postgresql"
    }
  )
}

#checkov:skip=CKV_AWS_382:Outbound internet access required for testing environment
resource "aws_security_group" "redis" {
  count       = var.deploy_redis ? 1 : 0
  name        = "${var.cluster_name}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = module.vpc[0].vpc_id

  ingress {
    description = "Redis access"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.redis_allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    #tfsec:ignore:aws-ec2-no-public-egress-sgr Outbound internet access required for testing environment
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-redis-sg"
      Service = "redis"
    }
  )
}

###########################################
# Subnet Groups
###########################################

resource "aws_db_subnet_group" "postgres" {
  count      = var.deploy_postgres ? 1 : 0
  name       = "${var.cluster_name}-postgres-subnet-group"
  subnet_ids = module.vpc[0].private_subnets

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-postgres-subnet-group"
      Service = "postgresql"
    }
  )
}

resource "aws_elasticache_subnet_group" "redis" {
  count      = var.deploy_redis ? 1 : 0
  name       = "${var.cluster_name}-redis-subnet-group"
  subnet_ids = module.vpc[0].private_subnets

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-redis-subnet-group"
      Service = "redis"
    }
  )
}

###########################################
# RDS PostgreSQL
###########################################

#checkov:skip=CKV_AWS_226:Auto minor version upgrades disabled to control upgrade timing in testing
#checkov:skip=CKV_AWS_129:RDS logs not required for ephemeral testing database
#checkov:skip=CKV_AWS_293:Deletion protection disabled for easier cleanup in testing environment
#checkov:skip=CKV_AWS_353:Performance insights not required for testing environment
#checkov:skip=CKV_AWS_161:IAM authentication not required for testing environment
#checkov:skip=CKV_AWS_157:Multi-AZ disabled for cost savings in testing environment
#checkov:skip=CKV_AWS_118:Enhanced monitoring not required for testing environment
#tfsec:ignore:aws-rds-enable-performance-insights Performance insights not required for testing environment
resource "aws_db_instance" "postgres" {
  count                   = var.deploy_postgres ? 1 : 0
  identifier              = "${var.cluster_name}-postgres"
  engine                  = "postgres"
  engine_version          = var.postgres_version
  instance_class          = var.postgres_instance_class
  allocated_storage       = var.postgres_allocated_storage
  storage_type            = "gp3"
  storage_encrypted       = true  # Fix HIGH: Enable encryption
  db_name                 = "eic"
  username                = var.postgres_admin_username
  password                = var.postgres_admin_password
  db_subnet_group_name    = aws_db_subnet_group.postgres[0].name
  vpc_security_group_ids  = [aws_security_group.postgres[0].id]
  publicly_accessible     = var.postgres_publicly_accessible
  skip_final_snapshot     = true
  backup_retention_period = 7
  multi_az                = false
  #tfsec:ignore:aws-rds-specify-backup-retention Backup retention already set to 7 days
  #tfsec:ignore:aws-rds-enable-deletion-protection Deletion protection disabled for easier cleanup in testing environment
  deletion_protection     = false
  #tfsec:ignore:aws-rds-enable-iam-auth IAM authentication not required for testing environment
  iam_database_authentication_enabled = false

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-postgres"
      Service = "postgresql"
    }
  )
}

###########################################
# ElastiCache Redis
###########################################

#checkov:skip=CKV_AWS_134:ElastiCache backup not required for ephemeral testing cache
#tfsec:ignore:aws-elasticache-enable-backup-retention Backup retention not required for testing cache
resource "aws_elasticache_cluster" "redis" {
  count                = var.deploy_redis ? 1 : 0
  cluster_id           = "${var.cluster_name}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis[0].name
  security_group_ids   = [aws_security_group.redis[0].id]

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-redis"
      Service = "redis"
    }
  )
}

