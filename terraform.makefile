# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# ROSA Configuration
ROSA_CLUSTER_NAME?=sapeic
ROSA_REGION?=us-east-1
ROSA_VERSION?=4.15.35

# AWS services configuration
DEPLOY_POSTGRES?=true
DEPLOY_REDIS?=true
POSTGRES_ADMIN_PASSWORD?=

# Terraform configuration
TF_DIR=terraform
TF_STATE_FILE=$(TF_DIR)/terraform.tfstate

.PHONY: rosa-prerequisites
rosa-prerequisites:  ## Check and install ROSA prerequisites
	$(call required-environment-variables,AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY ROSA_TOKEN)
	@echo "🔍 Checking ROSA CLI installation..."
	@which rosa >/dev/null || (echo "❌ ROSA CLI not found. Installing..." && curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar -xz && sudo mv rosa /usr/local/bin/)
	@echo "🔍 Checking AWS CLI installation..."
	@which aws >/dev/null || (echo "❌ AWS CLI not found. Installing..." && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install)
	@echo "🔍 Checking Terraform installation..."
	@which terraform >/dev/null || (echo "❌ Terraform not found. Installing..." && curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - && sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && sudo apt-get update && sudo apt-get install terraform)
	@echo "✅ All prerequisites are installed!"

.PHONY: rosa-login
rosa-login:  ## Login using ROSA token
	$(call required-environment-variables,ROSA_TOKEN)
	@echo "🔐 Logging into ROSA..."
	@rosa login --token="${ROSA_TOKEN}"

.PHONY: rosa-init
rosa-init:  ## Initialize ROSA
	@echo "🚀 Initializing ROSA..."
	@rosa init

.PHONY: rosa-account-roles
rosa-account-roles:  ## Create AWS account roles for ROSA
	@echo "🏗️ Creating AWS account roles for ROSA..."
	@rosa create account-roles --mode auto

.PHONY: terraform-init
terraform-init:  ## Initialize Terraform
	@echo "🔧 Initializing Terraform..."
	@cd $(TF_DIR) && terraform init

.PHONY: terraform-plan
terraform-plan: terraform-init  ## Plan Terraform deployment
	$(call required-environment-variables,AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY)
	@echo "📋 Planning Terraform deployment..."
	@cd $(TF_DIR) && terraform plan \
		-var="cluster_name=$(ROSA_CLUSTER_NAME)" \
		-var="region=$(ROSA_REGION)" \
		-var="deploy_postgres=$(DEPLOY_POSTGRES)" \
		-var="deploy_redis=$(DEPLOY_REDIS)" \
		-var="postgres_admin_password=$(POSTGRES_ADMIN_PASSWORD)"

.PHONY: terraform-apply
terraform-apply: terraform-init  ## Apply Terraform infrastructure
	$(call required-environment-variables,AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY)
	@echo "🚀 Applying Terraform infrastructure..."
	@cd $(TF_DIR) && terraform apply -auto-approve \
		-var="cluster_name=$(ROSA_CLUSTER_NAME)" \
		-var="region=$(ROSA_REGION)" \
		-var="deploy_postgres=$(DEPLOY_POSTGRES)" \
		-var="deploy_redis=$(DEPLOY_REDIS)" \
		-var="postgres_admin_password=$(POSTGRES_ADMIN_PASSWORD)"

.PHONY: rosa-cluster-create
rosa-cluster-create:  ## Create ROSA cluster
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME)
	@echo "🏗️ Creating ROSA cluster..."
	@rosa create cluster \
		--cluster-name "$(ROSA_CLUSTER_NAME)" \
		--region "$(ROSA_REGION)" \
		--version "$(ROSA_VERSION)" \
		--compute-nodes 3 \
		--machine-cidr 10.0.0.0/16 \
		--service-cidr 172.30.0.0/16 \
		--pod-cidr 10.128.0.0/14 \
		--host-prefix 23 \
		--private-link \
		--yes

.PHONY: rosa-cluster-status
rosa-cluster-status:  ## Get ROSA cluster status
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME)
	@echo "📊 Getting ROSA cluster status..."
	@rosa describe cluster --cluster "$(ROSA_CLUSTER_NAME)"

.PHONY: rosa-cluster-wait
rosa-cluster-wait:  ## Wait for ROSA cluster to be ready
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME)
	@echo "⏳ Waiting for ROSA cluster to be ready..."
	@rosa logs install --cluster "$(ROSA_CLUSTER_NAME)" --watch

.PHONY: rosa-cluster-admin
rosa-cluster-admin:  ## Create cluster admin
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME CLUSTER_ADMIN_PASSWORD)
	@echo "👤 Creating cluster admin..."
	@rosa create admin --cluster $(ROSA_CLUSTER_NAME) --password $(CLUSTER_ADMIN_PASSWORD) >/dev/null
	@echo "✅ Cluster admin created"

.PHONY: rosa-cluster-admin-reset
rosa-cluster-admin-reset:  ## Reset cluster admin password
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME CLUSTER_ADMIN_PASSWORD)
	@echo "🔄 Resetting cluster admin password..."
	@rosa delete admin --cluster $(ROSA_CLUSTER_NAME) --yes >/dev/null
	@echo "🗑️ Cluster admin deleted"
	@rosa create admin --cluster $(ROSA_CLUSTER_NAME) --password $(CLUSTER_ADMIN_PASSWORD) >/dev/null
	@echo "✅ Cluster admin password reset"

.PHONY: rosa-cluster-oc-login
rosa-cluster-oc-login:  ## OC CLI login to existing cluster
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME)
	@echo "🔐 Logging into cluster with OC CLI..."
	@rosa describe admin --cluster=$(ROSA_CLUSTER_NAME) | grep -v 'INFO'

.PHONY: rosa-deploy
rosa-deploy: rosa-prerequisites rosa-login terraform-apply rosa-cluster-create rosa-cluster-wait  ## Deploy complete ROSA environment

.PHONY: terraform-output
terraform-output:  ## Get Terraform outputs
	@echo "📤 Getting Terraform outputs..."
	@cd $(TF_DIR) && terraform output -json

.PHONY: aws-services-info
aws-services-info:  ## Get AWS services information
	@echo "=== AWS Services Information ==="
	@cd $(TF_DIR) && terraform output -json | jq -r '
		"VPC ID: " + (.vpc_id.value // "Not deployed") + "\n" +
		"PostgreSQL Endpoint: " + (.postgres_endpoint.value // "Not deployed") + "\n" +
		"PostgreSQL Database: sapeic\n" +
		"PostgreSQL Admin: postgres\n" +
		"Redis Endpoint: " + (.redis_endpoint.value // "Not deployed") + "\n" +
		"Redis Port: " + (.redis_port.value // "Not deployed")
	'

.PHONY: rosa-cluster-hibernate
rosa-cluster-hibernate:  ## Hibernate ROSA cluster
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME)
	@echo "😴 Hibernating ROSA cluster..."
	@rosa hibernate cluster --cluster "$(ROSA_CLUSTER_NAME)"

.PHONY: rosa-cluster-resume
rosa-cluster-resume:  ## Resume ROSA cluster
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME)
	@echo "🌅 Resuming ROSA cluster..."
	@rosa resume cluster --cluster "$(ROSA_CLUSTER_NAME)"

.PHONY: rosa-cluster-delete
rosa-cluster-delete:  ## Delete ROSA cluster
	$(call required-environment-variables,ROSA_TOKEN ROSA_CLUSTER_NAME)
	@echo "🗑️ Deleting ROSA cluster..."
	@rosa delete cluster --cluster "$(ROSA_CLUSTER_NAME)" --yes

.PHONY: terraform-destroy
terraform-destroy:  ## Destroy Terraform infrastructure
	$(call required-environment-variables,AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY)
	@echo "🗑️ Destroying Terraform infrastructure..."
	@cd $(TF_DIR) && terraform destroy -auto-approve \
		-var="cluster_name=$(ROSA_CLUSTER_NAME)" \
		-var="region=$(ROSA_REGION)" \
		-var="deploy_postgres=$(DEPLOY_POSTGRES)" \
		-var="deploy_redis=$(DEPLOY_REDIS)" \
		-var="postgres_admin_password=$(POSTGRES_ADMIN_PASSWORD)"

.PHONY: rosa-cleanup
rosa-cleanup: rosa-cluster-delete terraform-destroy  ## Complete cleanup of ROSA environment

.PHONY: oc-login
oc-login:  ## Login with oc to existing ROSA cluster
	$(call required-environment-variables,ROSA_CLUSTER_NAME)
	@echo "🔐 Logging into ROSA cluster with OC CLI..."
	@rosa describe admin --cluster=$(ROSA_CLUSTER_NAME) | grep -v 'INFO'

# Helper function for required environment variables
define required-environment-variables
	$(foreach var,$(1),$(if $($(var)),,$(error Environment variable $(var) is required)))
endef 