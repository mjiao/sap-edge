# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Kirill Satarin (@kksat)
# SPDX-FileContributor: Manjun Jiao (@mjiao)
# SPDX-FileContributor: Rishabh Bhandari (@RishabhKodes)

# SPDX-License-Identifier: Apache-2.0

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "rosa-vpc"
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "rosa-hcp-cluster"
}

variable "rosa_version" {
  type        = string
  description = "ROSA openshift version"
  default     = "4.14.9"
}

variable "tags" {
  default = {
    Terraform   = "true"
    Environment = "test"
  }
  description = "Tags for created AWS resources"
  type        = map(string)
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

###########################################
# AWS Services Variables
###########################################

variable "deploy_postgres" {
  description = "Deploy AWS RDS PostgreSQL"
  type        = bool
  default     = false  # Disabled by default - enable with TF_VAR_deploy_postgres=true
}

variable "deploy_redis" {
  description = "Deploy AWS ElastiCache Redis"
  type        = bool
  default     = false  # Disabled by default - enable with TF_VAR_deploy_redis=true
}

# PostgreSQL Configuration
variable "postgres_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.5"
}

variable "postgres_instance_class" {
  description = "RDS instance class (cost-optimized for testing)"
  type        = string
  default     = "db.t3.micro"
}

variable "postgres_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "postgres_admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "eicadmin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
  default     = ""  # Set via TF_VAR_postgres_admin_password or terraform.tfvars
}

variable "postgres_publicly_accessible" {
  description = "Make PostgreSQL publicly accessible"
  type        = bool
  default     = false
}

variable "postgres_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access PostgreSQL"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# Redis Configuration
variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_node_type" {
  description = "ElastiCache node type (cost-optimized for testing)"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Redis"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}
