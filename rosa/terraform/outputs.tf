# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-License-Identifier: Apache-2.0

###########################################
# ROSA Cluster Outputs
###########################################

output "rosa_cluster_id" {
  description = "The ID of the ROSA cluster"
  value       = try(module.rosa-hcp.cluster_id, "")
}

output "rosa_cluster_name" {
  description = "The name of the ROSA cluster"
  value       = var.cluster_name
}

output "rosa_account_role_prefix" {
  description = "The account role prefix"
  value       = try(module.rosa-hcp.account_role_prefix, "")
}

output "rosa_operator_role_prefix" {
  description = "The operator role prefix"
  value       = try(module.rosa-hcp.operator_role_prefix, "")
}

###########################################
# VPC Outputs
###########################################

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc[0].vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc[0].vpc_cidr_block
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc[0].private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc[0].public_subnets
}

###########################################
# PostgreSQL Outputs
###########################################

output "postgres_endpoint" {
  description = "PostgreSQL endpoint"
  value       = var.deploy_postgres ? try(aws_db_instance.postgres[0].endpoint, "") : ""
}

output "postgres_address" {
  description = "PostgreSQL address"
  value       = var.deploy_postgres ? try(aws_db_instance.postgres[0].address, "") : ""
}

output "postgres_port" {
  description = "PostgreSQL port"
  value       = var.deploy_postgres ? try(aws_db_instance.postgres[0].port, 0) : 0
}

output "postgres_database_name" {
  description = "PostgreSQL database name"
  value       = var.deploy_postgres ? try(aws_db_instance.postgres[0].db_name, "") : ""
}

output "postgres_admin_username" {
  description = "PostgreSQL admin username"
  value       = var.deploy_postgres ? var.postgres_admin_username : ""
}

output "postgres_admin_password" {
  description = "PostgreSQL admin password"
  value       = var.deploy_postgres ? var.postgres_admin_password : ""
  sensitive   = true
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string (password not included for display)"
  value       = var.deploy_postgres ? try("postgresql://${var.postgres_admin_username}:[PASSWORD]@${aws_db_instance.postgres[0].endpoint}/eic?sslmode=require", "") : ""
}

output "postgres_connection_string_full" {
  description = "PostgreSQL full connection string with password"
  value       = var.deploy_postgres ? try("postgresql://${var.postgres_admin_username}:${var.postgres_admin_password}@${aws_db_instance.postgres[0].endpoint}/eic?sslmode=require", "") : ""
  sensitive   = true
}

output "postgres_ca_cert_url" {
  description = "URL to download AWS RDS CA certificate bundle"
  value       = var.deploy_postgres ? "https://truststore.pki.rds.amazonaws.com/${var.aws_region}/${var.aws_region}-bundle.pem" : ""
}

###########################################
# Redis Outputs
###########################################

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = var.deploy_redis ? try(aws_elasticache_replication_group.redis[0].primary_endpoint_address, "") : ""
}

output "redis_port" {
  description = "Redis port"
  value       = var.deploy_redis ? try(aws_elasticache_replication_group.redis[0].port, 0) : 0
}

output "redis_auth_token" {
  description = "Redis authentication token"
  value       = var.deploy_redis ? try(random_password.redis_auth_token[0].result, "") : ""
  sensitive   = true
}

output "redis_connection_string" {
  description = "Redis connection string (auth token not included for display, use rediss:// for TLS)"
  value       = var.deploy_redis ? try("rediss://:[AUTH_TOKEN]@${aws_elasticache_replication_group.redis[0].primary_endpoint_address}:${aws_elasticache_replication_group.redis[0].port}/0", "") : ""
}

output "redis_connection_string_full" {
  description = "Redis full connection string with auth token"
  value       = var.deploy_redis ? try("rediss://:${random_password.redis_auth_token[0].result}@${aws_elasticache_replication_group.redis[0].primary_endpoint_address}:${aws_elasticache_replication_group.redis[0].port}/0", "") : ""
  sensitive   = true
}

output "redis_ca_cert_url" {
  description = "URL to download Amazon Root CA certificate for ElastiCache TLS (usually not needed - already trusted by system)"
  value       = var.deploy_redis ? "https://www.amazontrust.com/repository/AmazonRootCA1.pem" : ""
}

###########################################
# Quay Storage Outputs
###########################################

output "quay_s3_bucket_name" {
  description = "S3 bucket name for Quay registry"
  value       = var.deploy_quay ? try(aws_s3_bucket.quay[0].id, "") : ""
}

output "quay_s3_bucket_region" {
  description = "S3 bucket region for Quay registry"
  value       = var.deploy_quay ? try(aws_s3_bucket.quay[0].region, "") : ""
}

output "quay_s3_access_key_id" {
  description = "IAM access key ID for Quay S3 access"
  value       = var.deploy_quay ? try(aws_iam_access_key.quay[0].id, "") : ""
  sensitive   = true
}

output "quay_s3_secret_access_key" {
  description = "IAM secret access key for Quay S3 access"
  value       = var.deploy_quay ? try(aws_iam_access_key.quay[0].secret, "") : ""
  sensitive   = true
}
