# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

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

variable "postgres_instance_class" {
  description = "RDS PostgreSQL instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "postgres_allocated_storage" {
  description = "RDS PostgreSQL allocated storage in GB"
  type        = number
  default     = 20
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "development"
    Project     = "sap-edge"
    ManagedBy   = "terraform"
  }
} 