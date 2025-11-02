# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-License-Identifier: Apache-2.0

###########################################
# PostgreSQL Outputs
###########################################

output "postgres_endpoint" {
  description = "PostgreSQL endpoint"
  value       = var.deploy_postgres ? aws_db_instance.postgres[0].endpoint : ""
}

output "postgres_address" {
  description = "PostgreSQL address"
  value       = var.deploy_postgres ? aws_db_instance.postgres[0].address : ""
}

output "postgres_port" {
  description = "PostgreSQL port"
  value       = var.deploy_postgres ? aws_db_instance.postgres[0].port : 0
}

output "postgres_database_name" {
  description = "PostgreSQL database name"
  value       = var.deploy_postgres ? aws_db_instance.postgres[0].db_name : ""
}

output "postgres_admin_username" {
  description = "PostgreSQL admin username"
  value       = var.deploy_postgres ? var.postgres_admin_username : ""
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string (password not included)"
  value       = var.deploy_postgres ? "postgresql://${var.postgres_admin_username}:[PASSWORD]@${aws_db_instance.postgres[0].endpoint}/eic?sslmode=require" : ""
}

###########################################
# Redis Outputs
###########################################

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = var.deploy_redis ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : ""
}

output "redis_port" {
  description = "Redis port"
  value       = var.deploy_redis ? aws_elasticache_cluster.redis[0].cache_nodes[0].port : 0
}

output "redis_connection_string" {
  description = "Redis connection string"
  value       = var.deploy_redis ? "redis://${aws_elasticache_cluster.redis[0].cache_nodes[0].address}:${aws_elasticache_cluster.redis[0].cache_nodes[0].port}" : ""
}
