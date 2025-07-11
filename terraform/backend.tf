# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# Terraform backend configuration for state management
# Uncomment and configure as needed for your environment

# Example S3 backend configuration
# terraform {
#   backend "s3" {
#     bucket = "your-terraform-state-bucket"
#     key    = "rosa/terraform.tfstate"
#     region = "us-east-1"
#   }
# }

# Example local backend (default)
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
} 