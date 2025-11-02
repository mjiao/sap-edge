# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Kirill Satarin (@kksat)
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

module "rosa-hcp" {
  source  = "terraform-redhat/rosa-hcp/rhcs"
  version = "1.6.2"

  cluster_name           = var.cluster_name
  openshift_version      = var.rosa_version
  machine_cidr           = module.vpc[0].vpc_cidr_block
  aws_subnet_ids         = concat(module.vpc[0].private_subnets, module.vpc[0].public_subnets)
  aws_availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
  replicas               = 3
  
  # Create account-wide and operator IAM roles
  create_account_roles  = true
  account_role_prefix   = var.cluster_name
  create_oidc           = true
  create_operator_roles = true
  operator_role_prefix  = var.cluster_name
}
