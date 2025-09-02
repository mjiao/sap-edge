# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Kirill Satarin (@kksat)
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

ARO_RESOURCE_GROUP?=aro-sapeic
ARO_LOCATION?=northeurope

ARO_CLUSTER_NAME?=sapeic
ARO_DOMAIN?=saponrhel.org
ARO_VERSION?=4.15.35

# Azure services configuration
DEPLOY_POSTGRES?=true
DEPLOY_REDIS?=true
POSTGRES_ADMIN_PASSWORD?=

.PHONY: install-bicep
install-bicep:
	az config set bicep.use_binary_from_path=false && az bicep install && az bicep version

.PHONY: lint-bicep
lint-bicep: install-bicep ## Run bicep lint
	az bicep lint --file bicep/aro.bicep
	az bicep lint --file bicep/domain-records.bicep


.PHONY: domain-records
.ONESHELL:
domain-records:  ## Create domain records for ARO
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME ARO_DOMAIN)
	hack/domain-records.sh \
		--domain ${ARO_DOMAIN} \
		--aro-name ${ARO_CLUSTER_NAME} \
		--aro-resource-group ${ARO_RESOURCE_GROUP}

.PHONY: network-deploy
network-deploy:  ## Deploy network
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	az deployment group create --resource-group ${ARO_RESOURCE_GROUP} \
		--template-file bicep/network.bicep

.PHONY: resource-group
resource-group:  ## Create resource group
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_LOCATION)
	az group create --name ${ARO_RESOURCE_GROUP} --location ${ARO_LOCATION} --query name -o tsv

.PHONY: azure-login
azure-login:  ## Login to Azure using service principal
	$(call required-environment-variables,CLIENT_ID CLIENT_SECRET TENANT_ID)
	@echo "🔐 Logging into Azure with service principal..."
	@az login --service-principal -u "${CLIENT_ID}" -p "${CLIENT_SECRET}" --tenant "${TENANT_ID}" > /dev/null 2>&1 || { echo "❌ Azure login failed"; exit 1; }
	@echo "✅ Azure login successful"

.PHONY: azure-set-subscription
azure-set-subscription:  ## Set Azure subscription to current account
	az account set --subscription "$$(az account show --query id -o tsv)"

.PHONY: aro-cluster-status
aro-cluster-status:  ## Get ARO cluster provisioning state
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	@az aro show --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" --query "provisioningState" -o tsv

.PHONY: aro-cluster-exists
aro-cluster-exists:  ## Check if ARO cluster exists
	@if [ -z "${ARO_CLUSTER_NAME}" ] || [ -z "${ARO_RESOURCE_GROUP}" ]; then \
		echo "false"; \
	else \
		az aro show --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" >/dev/null 2>&1 && echo "true" || echo "false"; \
	fi

.PHONY: aro-cluster-url
aro-cluster-url:  ## Get ARO cluster URL
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	@az aro show --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" --query "apiserverProfile.url" -o tsv

.PHONY: aro-credentials
aro-credentials:  ## Get ARO credentials
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@az aro list-credentials --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP}

.PHONY: aro-kubeconfig
aro-kubeconfig:  ## Get ARO kubeconfig file
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@az aro get-admin-kubeconfig --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP}

.PHONY: postgres-exists
postgres-exists:  ## Check if PostgreSQL server exists
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@az postgres flexible-server show --resource-group "${ARO_RESOURCE_GROUP}" --name "postgres-${ARO_CLUSTER_NAME}" --query "name" -o tsv 2>/dev/null || echo ""

.PHONY: redis-exists
redis-exists:  ## Check if Redis cache exists
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@az redis list --resource-group "${ARO_RESOURCE_GROUP}" --query "[?contains(name, 'redis-${ARO_CLUSTER_NAME}')].name" -o tsv

.PHONY: service-principal
.ONESHELL:
service-principal:  ## Create service principal for ARO deployment
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	az ad sp create-for-rbac \
		--name "aro-service-principal" \
		--role Contributor \
		--scopes \
		"/subscriptions/$$(az account show --query id -o tsv)/resourceGroups/${ARO_RESOURCE_GROUP}"


.PHONY: arorp-service-principal
.ONESHELL:
arorp-service-principal:  ## Assign required roles to "Azure Red Hat Openshift" RP service principal
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	az role assignment create --assignee $$(az ad sp list --display-name "Azure Red Hat OpenShift RP" --query "[0].id" -o tsv) \
	--role Contributor \
	--scope "/subscriptions/$$(az account show --query id -o tsv)/resourceGroups/${ARO_RESOURCE_GROUP}"




.PHONY: aro-services-info
aro-services-info:  ## Get Azure services information
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	@echo "=== Azure Services Information ==="
	@az deployment group show --resource-group ${ARO_RESOURCE_GROUP} --name aro-deploy-${ARO_CLUSTER_NAME} --query "properties.outputs" -o json | jq -r '
		"PostgreSQL Server: " + (.postgresServerName.value // "Not deployed") + "\n" +
		"PostgreSQL FQDN: " + (.postgresServerFqdn.value // "Not deployed") + "\n" +
		"PostgreSQL Admin: " + (.postgresAdminUsername.value // "Not deployed") + "\n" +
		"PostgreSQL Database: " + (.postgresDatabaseName.value // "Not deployed") + "\n" +
		"Redis Cache: " + (.redisCacheName.value // "Not deployed") + "\n" +
		"Redis Host: " + (.redisHostName.value // "Not deployed") + "\n" +
		"Redis Port: " + (.redisPort.value // "Not deployed") + "\n" +
		"Redis SSL Port: " + (.redisSslPort.value // "Not deployed")
	'

.PHONY: domain-zone-exists
domain-zone-exists:  ## Fail if DNS domain zone does not exists
	$(call required-environment-variables,ARO_DOMAIN)
	ARO_DOMAIN=${ARO_DOMAIN} hack/domain-zone-exists.sh

.PHONY: oc-login
oc-login:  ## Login with oc to existing ARO cluster
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	oc login "$(shell az aro show --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP} --query "apiserverProfile.url" -o tsv)" \
		-u "$(shell az aro list-credentials --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP} --query 'kubeadminUsername' -o tsv)" \
		-p "$(shell az aro list-credentials --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP} --query 'kubeadminPassword' -o tsv)"

.PHONY: aro-resource-group-delete
aro-resource-group-delete:  ## Delete the Azure resource group
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	az group delete --name ${ARO_RESOURCE_GROUP} --yes --no-wait

.PHONY: aro-delete-cluster
aro-delete-cluster:  ## Delete the ARO cluster
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	az aro delete --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP} --yes --no-wait

.PHONY: aro-delete-resources
aro-delete-resources:  ## Delete all resources in the ARO resource group
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	az resource delete --resource-group ${ARO_RESOURCE_GROUP} --ids $$(az resource list --resource-group ${ARO_RESOURCE_GROUP} --query "[].id" -o tsv)




.PHONY: aro-cleanup-failed
aro-cleanup-failed:  ## Force delete failed ARO cluster
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	az aro delete --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP} --yes --no-wait

.PHONY: aro-wait-for-ready
aro-wait-for-ready:  ## Wait for ARO cluster to reach ready state
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	@WAIT_COUNT=0; \
	MAX_WAIT=120; \
	while [ $$WAIT_COUNT -lt $$MAX_WAIT ]; do \
		if STATUS=$$(az aro show --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" --query "provisioningState" -o tsv 2>/dev/null); then \
			echo "Cluster status: $$STATUS"; \
			if [ "$$STATUS" = "Succeeded" ]; then \
				echo "✅ Cluster is ready!"; \
				break; \
			elif [ "$$STATUS" = "Failed" ]; then \
				echo "❌ Cluster deployment failed"; \
				exit 1; \
			else \
				echo "⏳ Still provisioning... waiting 60 seconds ($$WAIT_COUNT/$$MAX_WAIT)"; \
			fi; \
		else \
			echo "❌ Cluster '${ARO_CLUSTER_NAME}' not found in resource group '${ARO_RESOURCE_GROUP}'"; \
			echo "💡 The cluster may have failed to deploy or was deleted"; \
			exit 1; \
		fi; \
		sleep 60; \
		WAIT_COUNT=$$((WAIT_COUNT + 1)); \
	done; \
	if [ $$WAIT_COUNT -ge $$MAX_WAIT ]; then \
		echo "❌ Timeout waiting for cluster to be ready after $$((MAX_WAIT * 60)) seconds"; \
		exit 1; \
	fi

.PHONY: aro-services-deploy-with-retry
aro-services-deploy-with-retry:  ## Deploy Azure services with retry logic
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME POSTGRES_ADMIN_PASSWORD)
	@RETRY_COUNT=0; \
	MAX_RETRIES=3; \
	while [ $$RETRY_COUNT -lt $$MAX_RETRIES ]; do \
		if make aro-services-deploy-test; then \
			echo "✅ Azure services deployment succeeded"; \
			break; \
		else \
			RETRY_COUNT=$$((RETRY_COUNT + 1)); \
			echo "❌ Deployment attempt $$RETRY_COUNT failed"; \
			if [ $$RETRY_COUNT -lt $$MAX_RETRIES ]; then \
				echo "⏳ Retrying in 30 seconds..."; \
				sleep 30; \
			else \
				echo "💥 All deployment attempts failed"; \
				exit 1; \
			fi; \
		fi; \
	done

.PHONY: aro-final-safety-check
aro-final-safety-check:  ## Final safety check before deployment to avoid conflicts
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	@if az aro show --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" >/dev/null 2>&1; then \
		echo "⚠️ WARNING: Cluster detected during final check - skipping deployment to avoid conflicts"; \
		echo "✅ ARO deployment completed successfully (cluster already exists)"; \
		exit 0; \
	else \
		echo "🔍 Final safety check passed - no existing cluster found"; \
	fi

.PHONY: aro-get-kubeconfig
aro-get-kubeconfig:  ## Get ARO kubeconfig with insecure TLS settings
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	@echo "🔐 Getting ARO kubeconfig..."
	rm -f kubeconfig kubeconfig.backup
	az aro get-admin-kubeconfig --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" --file kubeconfig
	echo "🔧 Adding insecure TLS settings to kubeconfig..."
	cp kubeconfig kubeconfig.backup
	sed '/^    server:/a\    insecure-skip-tls-verify: true' kubeconfig.backup > kubeconfig
	echo "✅ Kubeconfig ready with insecure TLS settings"

.PHONY: redis-get-info
redis-get-info:  ## Get Redis cache connection information
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@REDIS_LIST=$$(make redis-exists | tail -1); \
	if [[ -n "$$REDIS_LIST" ]]; then \
		REDIS_CACHE_NAME=$$(echo "$$REDIS_LIST" | head -1); \
		echo "Redis Cache Name: $$REDIS_CACHE_NAME"; \
		echo "Redis Host: $$(az redis show --resource-group "${ARO_RESOURCE_GROUP}" --name "$$REDIS_CACHE_NAME" --query "hostName" -o tsv)"; \
		echo "Redis Port: $$(az redis show --resource-group "${ARO_RESOURCE_GROUP}" --name "$$REDIS_CACHE_NAME" --query "port" -o tsv)"; \
		echo "Redis SSL Port: $$(az redis show --resource-group "${ARO_RESOURCE_GROUP}" --name "$$REDIS_CACHE_NAME" --query "sslPort" -o tsv)"; \
		echo "Redis Access Key: $$(az redis list-keys --resource-group "${ARO_RESOURCE_GROUP}" --name "$$REDIS_CACHE_NAME" --query "primaryKey" -o tsv)"; \
	else \
		echo "No Redis cache found"; \
	fi

.PHONY: postgres-delete
postgres-delete:  ## Delete PostgreSQL flexible server
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@if az postgres flexible-server show --resource-group "${ARO_RESOURCE_GROUP}" --name "postgres-${ARO_CLUSTER_NAME}" >/dev/null 2>&1; then \
		echo "🗑️ Deleting PostgreSQL server postgres-${ARO_CLUSTER_NAME}..."; \
		az postgres flexible-server delete --resource-group "${ARO_RESOURCE_GROUP}" --name "postgres-${ARO_CLUSTER_NAME}" --yes; \
		echo "✅ PostgreSQL server deletion initiated"; \
	else \
		echo "ℹ️ PostgreSQL server not found"; \
	fi

.PHONY: redis-delete
redis-delete:  ## Delete Redis cache instances
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@REDIS_CACHES=$$(az redis list --resource-group "${ARO_RESOURCE_GROUP}" --query "[?contains(name, 'redis-${ARO_CLUSTER_NAME}')].name" -o tsv); \
	if [[ -n "$$REDIS_CACHES" ]]; then \
		for redis_name in $$REDIS_CACHES; do \
			echo "🗑️ Deleting Redis cache: $$redis_name"; \
			az redis delete --resource-group "${ARO_RESOURCE_GROUP}" --name "$$redis_name" --yes; \
		done; \
		echo "✅ Redis cache deletion initiated"; \
	else \
		echo "ℹ️ Redis cache not found"; \
	fi

.PHONY: aro-resources-cleanup
aro-resources-cleanup:  ## Clean up other ARO-related resources
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@ARO_RESOURCES=$$(az resource list --resource-group "${ARO_RESOURCE_GROUP}" --query "[?contains(name, '${ARO_CLUSTER_NAME}') || (tags && tags.cluster && contains(tags.cluster, '${ARO_CLUSTER_NAME}'))].id" -o tsv); \
	if [[ -n "$$ARO_RESOURCES" ]]; then \
		echo "Found other ARO-related resources to delete:"; \
		echo "$$ARO_RESOURCES"; \
		az resource delete --resource-group "${ARO_RESOURCE_GROUP}" --ids $$ARO_RESOURCES --yes || echo "Some ARO resources may have already been deleted"; \
		echo "✅ ARO resources cleanup completed"; \
	else \
		echo "ℹ️ No other ARO-related resources found"; \
	fi

.PHONY: aro-resource-group-create
aro-resource-group-create:  ## Create resource group (idempotent)
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_LOCATION)
	@echo "🏗️ Creating resource group ${ARO_RESOURCE_GROUP}..."
	az group create --name "${ARO_RESOURCE_GROUP}" --location "${ARO_LOCATION}" --query name -o tsv || echo "Resource group already exists"

.PHONY: aro-resource-group-exists
aro-resource-group-exists:  ## Check if resource group exists
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	@az group show --name "${ARO_RESOURCE_GROUP}" >/dev/null 2>&1

.PHONY: aro-cleanup-all-services
aro-cleanup-all-services:  ## Clean up all ARO services (PostgreSQL, Redis, other resources)
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@echo "🧹 Cleaning up ARO-related resources..."
	make postgres-delete
	make redis-delete
	make aro-resources-cleanup

# Testing-optimized deployment targets
.PHONY: aro-deploy-only
aro-deploy-only:  ## Deploy ARO cluster only (no PostgreSQL/Redis services)
	$(call required-environment-variables,ARO_RESOURCE_GROUP CLIENT_ID CLIENT_SECRET TENANT_ID PULL_SECRET)
	@echo "🧪 Deploying ARO cluster only (no Azure services)..."
	@echo "🔍 Checking if cluster already exists..."
	@CLUSTER_CHECK_RESULT=$$(make --no-print-directory aro-cluster-exists 2>/dev/null | grep -E '^(true|false)$$' | tail -1); \
	echo "🔍 Cluster check result: '$$CLUSTER_CHECK_RESULT'"; \
	if [ "$$CLUSTER_CHECK_RESULT" = "true" ]; then \
		echo "✅ ARO cluster '${ARO_CLUSTER_NAME}' already exists. Skipping deployment."; \
		exit 0; \
	else \
		echo "🔍 Cluster '${ARO_CLUSTER_NAME}' not found, proceeding with deployment..."; \
	fi
	@echo "🔍 Checking for running deployments..."
	@EXISTING_STATE=$$(az deployment group show --resource-group ${ARO_RESOURCE_GROUP} --name aro-deploy-${ARO_CLUSTER_NAME} --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NotFound"); \
	if [ "$$EXISTING_STATE" = "Running" ]; then \
		echo "⏳ Found deployment in progress. Waiting for completion..."; \
		while [ "$$(az deployment group show --resource-group ${ARO_RESOURCE_GROUP} --name aro-deploy-${ARO_CLUSTER_NAME} --query "properties.provisioningState" -o tsv 2>/dev/null)" = "Running" ]; do \
			echo "⏳ Still running... waiting 60 seconds"; \
			sleep 60; \
		done; \
	fi
	@echo "🔐 Preparing secure deployment parameters..."
	@PULL_SECRET_BASE64=$$(printf '%s' "$$PULL_SECRET" | tr -d '\n' | sed 's/^"//;s/"$$//' | base64 -w 0); \
	TEMP_PARAMS=$$(mktemp); \
	echo "{ \
		\"clusterName\": { \"value\": \"${ARO_CLUSTER_NAME}\" }, \
		\"domain\": { \"value\": \"${ARO_CLUSTER_NAME}.${ARO_DOMAIN}\" }, \
		\"servicePrincipalClientId\": { \"value\": \"${CLIENT_ID}\" }, \
		\"servicePrincipalClientSecret\": { \"value\": \"${CLIENT_SECRET}\" }, \
		\"pullSecret\": { \"value\": \"$$PULL_SECRET_BASE64\" }, \
		\"deployPostgres\": { \"value\": false }, \
		\"deployRedis\": { \"value\": false } \
	}" > $$TEMP_PARAMS; \
	echo "🚀 Starting Bicep deployment..."; \
	if az deployment group create --resource-group ${ARO_RESOURCE_GROUP} \
		--name aro-deploy-${ARO_CLUSTER_NAME} \
		--template-file bicep/aro.bicep \
		--parameters @bicep/test.parameters.json \
		--parameters @$$TEMP_PARAMS; then \
		echo "✅ Bicep deployment completed successfully"; \
	else \
		echo "❌ Bicep deployment failed"; \
		rm -f $$TEMP_PARAMS; \
		exit 1; \
	fi; \
	rm -f $$TEMP_PARAMS

.PHONY: aro-deploy-test
aro-deploy-test:  ## Deploy ARO with cost-optimized test settings
	$(call required-environment-variables,ARO_RESOURCE_GROUP CLIENT_ID CLIENT_SECRET TENANT_ID PULL_SECRET POSTGRES_ADMIN_PASSWORD)
	@echo "🧪 Deploying ARO cluster with test-optimized settings..."
	@echo "🔍 Checking if cluster already exists..."
	@if $$(make aro-cluster-exists | tail -1 | grep -q "true"); then \
		echo "✅ ARO cluster '${ARO_CLUSTER_NAME}' already exists. Skipping deployment."; \
		exit 0; \
	fi
	@echo "🔍 Checking for running deployments..."
	@EXISTING_STATE=$$(az deployment group show --resource-group ${ARO_RESOURCE_GROUP} --name aro-deploy-${ARO_CLUSTER_NAME} --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NotFound"); \
	if [ "$$EXISTING_STATE" = "Running" ]; then \
		echo "⏳ Found deployment in progress. Waiting for completion..."; \
		while [ "$$(az deployment group show --resource-group ${ARO_RESOURCE_GROUP} --name aro-deploy-${ARO_CLUSTER_NAME} --query "properties.provisioningState" -o tsv 2>/dev/null)" = "Running" ]; do \
			echo "⏳ Still running... waiting 60 seconds"; \
			sleep 60; \
		done; \
	fi
	@echo "🔐 Preparing secure deployment parameters..."
	@PULL_SECRET_BASE64=$$(printf '%s' "$$PULL_SECRET" | tr -d '\n' | sed 's/^"//;s/"$$//' | base64 -w 0); \
	TEMP_PARAMS=$$(mktemp); \
	echo "{ \
		\"clusterName\": { \"value\": \"${ARO_CLUSTER_NAME}\" }, \
		\"domain\": { \"value\": \"${ARO_CLUSTER_NAME}.${ARO_DOMAIN}\" }, \
		\"servicePrincipalClientId\": { \"value\": \"${CLIENT_ID}\" }, \
		\"servicePrincipalClientSecret\": { \"value\": \"${CLIENT_SECRET}\" }, \
		\"pullSecret\": { \"value\": \"$$PULL_SECRET_BASE64\" }, \
		\"postgresAdminPassword\": { \"value\": \"${POSTGRES_ADMIN_PASSWORD}\" } \
	}" > $$TEMP_PARAMS; \
	az deployment group create --resource-group ${ARO_RESOURCE_GROUP} \
		--name aro-deploy-${ARO_CLUSTER_NAME} \
		--template-file bicep/aro.bicep \
		--parameters @bicep/test.parameters.json \
		--parameters @$$TEMP_PARAMS; \
	rm -f $$TEMP_PARAMS

.PHONY: aro-services-deploy-test
aro-services-deploy-test:  ## Deploy only Azure services with test settings
	$(call required-environment-variables,ARO_RESOURCE_GROUP POSTGRES_ADMIN_PASSWORD)
	@echo "🧪 Deploying Azure services with test-optimized settings..."
	@az deployment group create --resource-group ${ARO_RESOURCE_GROUP} \
		--name azure-services-deploy-${ARO_CLUSTER_NAME} \
		--template-file bicep/azure-services.bicep \
		--parameters @bicep/azure-services.test.parameters.json \
		--parameters \
		clusterName="${ARO_CLUSTER_NAME}" \
		postgresAdminPassword="${POSTGRES_ADMIN_PASSWORD}"

.PHONY: aro-test-info
aro-test-info:  ## Get test cluster connection and service information
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	@echo "🧪 Test Cluster Information:"
	@echo "=========================="
	@az deployment group show --resource-group ${ARO_RESOURCE_GROUP} --name aro-deploy-${ARO_CLUSTER_NAME} \
		--query "properties.outputs.quickConnectionInfo.value" -o json | jq -r '
		"Cluster Info:",
		"  Name: " + .cluster.name,
		"  API Server: " + .cluster.apiServerUrl,
		"  Console: " + .cluster.consoleUrl,
		"  Version: " + .cluster.version,
		"",
		"Quick Commands:",
		"  Get Kubeconfig: " + .commands.getKubeconfig,
		"  Get Credentials: " + .commands.getCredentials,
		"",
		if .services.postgres then
			"PostgreSQL:",
			"  Server: " + .services.postgres.serverName,
			"  FQDN: " + .services.postgres.serverFqdn,
			"  Database: " + .services.postgres.databaseName,
			"  Connect: " + .services.postgres.connectCommand,
			""
		else "" end,
		if .services.redis then
			"Redis:",
			"  Cache: " + .services.redis.cacheName,
			"  Host: " + .services.redis.hostName,
			"  Port: " + (.services.redis.port | tostring),
			"  SSL Port: " + (.services.redis.sslPort | tostring),
			"  Get Keys: " + .services.redis.getKeysCommand,
			""
		else "" end,
		"Testing Info:",
		"  Auto Shutdown: " + (.testing.autoShutdown | tostring),
		"  Shutdown Time: " + .testing.shutdownTime,
		"  Cleanup: " + .testing.cleanupCommand
		'

.PHONY: aro-cost-estimate
aro-cost-estimate:  ## Get cost estimate for test deployment
	@echo "💰 Estimated Monthly Costs for Test Configuration:"
	@echo "================================================="
	@echo "ARO Cluster (3 workers, D4s_v3): ~$1,200-1,500/month"
	@echo "PostgreSQL (Standard_B1ms): ~$15-25/month"
	@echo "Redis (Basic C0): ~$16-20/month"
	@echo "Total Estimated: ~$1,250-1,550/month"
	@echo ""
	@echo "💡 Cost Optimization Tips:"
	@echo "- Use 'make aro-cleanup-all-services' when not testing"
	@echo "- Consider hibernating cluster overnight (manual process)"
	@echo "- Monitor usage with: az consumption usage list"

# Azure Storage for Quay Registry
.PHONY: aro-quay-storage-create
aro-quay-storage-create:  ## Create Azure storage account for Quay registry
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@echo "🏗️ Creating Azure storage account for Quay registry..."
	@CLUSTER_HASH=$$(echo "${ARO_CLUSTER_NAME}" | sha256sum | cut -c1-8); \
	STORAGE_ACCOUNT_NAME="quay$$CLUSTER_HASH$$(date +%s | tail -c 6)"; \
	echo "Storage account name: $$STORAGE_ACCOUNT_NAME (for cluster: ${ARO_CLUSTER_NAME})"; \
	az storage account create \
		--name "$$STORAGE_ACCOUNT_NAME" \
		--resource-group "${ARO_RESOURCE_GROUP}" \
		--location "${ARO_LOCATION}" \
		--sku Standard_LRS \
		--kind StorageV2 \
		--access-tier Hot \
		--tags purpose=quay cluster="${ARO_CLUSTER_NAME}" team=sap-edge; \
	STORAGE_KEY=$$(az storage account keys list --resource-group "${ARO_RESOURCE_GROUP}" --account-name "$$STORAGE_ACCOUNT_NAME" --query "[0].value" -o tsv); \
	az storage container create \
		--name "quay-registry" \
		--account-name "$$STORAGE_ACCOUNT_NAME" \
		--account-key "$$STORAGE_KEY"; \
	echo ""; \
	echo "✅ Azure storage created successfully!"; \
	echo "📋 Storage Configuration:"; \
	echo "   Account Name: $$STORAGE_ACCOUNT_NAME"; \
	echo "   Container: quay-registry"; \
	echo "   Resource Group: ${ARO_RESOURCE_GROUP}"; \
	echo ""; \
	echo "🔑 Set these environment variables for Quay deployment:"; \
	echo "   export AZURE_STORAGE_ACCOUNT_NAME=$$STORAGE_ACCOUNT_NAME"; \
	echo "   export AZURE_STORAGE_ACCOUNT_KEY=$$STORAGE_KEY"; \
	echo "   export AZURE_STORAGE_CONTAINER=quay-registry"

.PHONY: aro-quay-storage-info
aro-quay-storage-info:  ## Get Azure storage account information for Quay
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	@echo "📋 Quay Azure Storage Accounts:"
	@echo "==============================="
	@az storage account list --resource-group "${ARO_RESOURCE_GROUP}" --query "[?tags.purpose=='quay'].{Name:name,Location:location,Cluster:tags.cluster}" -o table

.PHONY: aro-quay-storage-delete
aro-quay-storage-delete:  ## Delete Azure storage account for Quay (requires AZURE_STORAGE_ACCOUNT_NAME)
	$(call required-environment-variables,ARO_RESOURCE_GROUP AZURE_STORAGE_ACCOUNT_NAME)
	@echo "🗑️ Deleting Azure storage account for Quay..."
	@echo "⚠️  This will permanently delete all registry data!"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		az storage account delete \
			--name "${AZURE_STORAGE_ACCOUNT_NAME}" \
			--resource-group "${ARO_RESOURCE_GROUP}" \
			--yes; \
		echo "✅ Storage account deleted"; \
	else \
		echo "❌ Deletion cancelled"; \
	fi

# ARO Quay Registry deployment targets
.PHONY: aro-quay-deploy
aro-quay-deploy:  ## Deploy Quay registry operator and instance on ARO with Azure storage
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP AZURE_STORAGE_ACCOUNT_NAME AZURE_STORAGE_ACCOUNT_KEY AZURE_STORAGE_CONTAINER)
	@echo "📦 Deploying Quay registry operator on ARO cluster..."
	oc apply -f edge-integration-cell/quay-registry/quay-operator-subscription.yaml
	@echo "⏳ Waiting for Quay operator to be ready..."
	@timeout 300 bash -c 'until oc get csv -n openshift-operators | grep -q "quay-operator.*Succeeded"; do echo "Waiting for operator..."; sleep 10; done'
	@echo "🔧 Creating Quay configuration with Azure storage..."
	@TEMP_CONFIG=$$(mktemp); \
	sed 's/AZURE_STORAGE_ACCOUNT_NAME_PLACEHOLDER/${AZURE_STORAGE_ACCOUNT_NAME}/g; s/AZURE_STORAGE_ACCOUNT_KEY_PLACEHOLDER/${AZURE_STORAGE_ACCOUNT_KEY}/g; s/AZURE_STORAGE_CONTAINER_PLACEHOLDER/${AZURE_STORAGE_CONTAINER}/g' \
		edge-integration-cell/quay-registry/quay-config-secret.yaml > $$TEMP_CONFIG; \
	oc apply -f $$TEMP_CONFIG; \
	rm -f $$TEMP_CONFIG
	@echo "🚀 Creating Quay registry instance..."
	oc apply -f edge-integration-cell/quay-registry/quay-registry.yaml
	@echo "✅ Quay deployment initiated on ARO"

.PHONY: aro-quay-wait-ready
aro-quay-wait-ready:  ## Wait for Quay registry to be ready on ARO
	@echo "⏳ Waiting for Quay registry to be ready on ARO..."
	@timeout 600 bash -c 'until oc get pods -n openshift-operators | grep -E "test-registry-.*Running" | wc -l | grep -q "[5-9]"; do echo "Waiting for Quay pods..."; sleep 30; done'
	@echo "⏳ Waiting for Quay registry endpoint to be available..."
	@timeout 300 bash -c 'until oc get quayregistry test-registry -o json 2>/dev/null | jq -r ".status.registryEndpoint // \"\"" | grep -q "https://"; do echo "Waiting for endpoint..."; sleep 10; done'
	@echo "✅ Quay registry is ready on ARO!"

.PHONY: aro-quay-info
aro-quay-info:  ## Get Quay registry connection information on ARO
	@echo "📋 ARO Quay Registry Information:"
	@echo "================================="
	@ENDPOINT=$$(oc get quayregistry test-registry -o json 2>/dev/null | jq -r '.status.registryEndpoint // "Not ready"'); \
	if [ "$$ENDPOINT" != "Not ready" ]; then \
		REGISTRY=$$(echo "$$ENDPOINT" | sed 's/^https:\/\///'); \
		echo "Registry Endpoint: $$ENDPOINT"; \
		echo "Registry Host: $$REGISTRY"; \
		echo "Admin User Path: $$REGISTRY/quayadmin"; \
		echo ""; \
		echo "🔑 Create admin user:"; \
		echo "make aro-quay-create-admin"; \
		echo ""; \
		echo "🔒 Trust certificate:"; \
		echo "make aro-quay-trust-cert"; \
	else \
		echo "❌ Quay registry not ready yet"; \
	fi

.PHONY: aro-quay-create-admin
aro-quay-create-admin:  ## Create Quay admin user on ARO
	$(call required-environment-variables,QUAY_ADMIN_PASSWORD QUAY_ADMIN_EMAIL)
	@echo "👤 Creating Quay admin user on ARO..."
	@ENDPOINT=$$(oc get quayregistry test-registry -o json | jq -r '.status.registryEndpoint'); \
	USER_CREATION_ENDPOINT="$$ENDPOINT/api/v1/user/initialize"; \
	echo "Creating user at: $$USER_CREATION_ENDPOINT"; \
	curl -X POST -k "$$USER_CREATION_ENDPOINT" \
		--header 'Content-Type: application/json' \
		--data '{"username": "quayadmin", "password":"${QUAY_ADMIN_PASSWORD}", "email": "${QUAY_ADMIN_EMAIL}", "access_token": true}' \
		--fail --show-error || echo "User may already exist"
	@echo "✅ Admin user creation completed on ARO"

.PHONY: aro-quay-trust-cert
aro-quay-trust-cert:  ## Configure ARO to trust Quay registry certificate
	@echo "🔒 Configuring ARO to trust Quay registry certificate..."
	@echo "📋 Getting Quay registry endpoint..."
	@ENDPOINT=$$(oc get quayregistry test-registry -o json | jq -r '.status.registryEndpoint'); \
	if [ "$$ENDPOINT" = "null" ] || [ -z "$$ENDPOINT" ]; then \
		echo "❌ Quay registry endpoint not ready. Run 'make aro-quay-wait-ready' first."; \
		exit 1; \
	fi; \
	REGISTRY=$$(echo "$$ENDPOINT" | sed 's/^https:\/\///'); \
	echo "Registry hostname: $$REGISTRY"; \
	echo "🔑 Extracting OpenShift ingress CA certificate..."; \
	caBundle="$$(oc get -n openshift-ingress-operator -o json secret/router-ca | jq -r '.data as $$d | $$d | keys[] | select(test("\\.(?:crt|pem)$$")) | $$d[.] | @base64d')"; \
	if [ -z "$$caBundle" ]; then \
		echo "❌ Failed to extract CA certificate"; \
		exit 1; \
	fi; \
	echo "$$caBundle" > quay-registry.crt; \
	echo "📝 Configuring cluster image registry trust..."; \
	cmName="$$(oc get images.config.openshift.io/cluster -o json | jq -r '.spec.additionalTrustedCA.name // "trusted-registry-cabundles"')"; \
	if oc get -n openshift-config "cm/$$cmName" 2>/dev/null; then \
		echo "Updating existing configmap: $$cmName"; \
		oc get -o json -n openshift-config "cm/$$cmName" | \
			jq '.data["'"$${REGISTRY//:/..}"'"] |= "'"$$caBundle"'"' | \
			oc replace -f - --force; \
	else \
		echo "Creating new configmap: $$cmName"; \
		oc create configmap -n openshift-config "$$cmName" \
			--from-literal="$${REGISTRY//:/..}=$$caBundle"; \
		oc patch images.config.openshift.io cluster --type=merge \
			-p '{"spec":{"additionalTrustedCA":{"name":"'"$$cmName"'"}}}'; \
	fi; \
	echo "✅ Certificate trust configured for $$REGISTRY"; \
	echo ""; \
	echo "⚠️  Note: OpenShift nodes may need to restart to pick up the new CA bundle."; \
	echo "🔍 Use 'make aro-quay-verify-trust' to test the configuration."

.PHONY: aro-quay-test-login
aro-quay-test-login:  ## Test login to ARO Quay registry (requires podman/docker)
	@echo "🧪 Testing Quay registry login on ARO..."
	@ENDPOINT=$$(oc get quayregistry test-registry -o json | jq -r '.status.registryEndpoint'); \
	REGISTRY=$$(echo "$$ENDPOINT" | sed 's/^https:\/\///'); \
	echo "Testing login to: $$REGISTRY/quayadmin"; \
	echo "Use podman login $$REGISTRY/quayadmin or docker login $$REGISTRY/quayadmin"

.PHONY: aro-quay-verify-trust
aro-quay-verify-trust:  ## Verify that ARO trusts the Quay registry certificate
	@echo "🔍 Verifying Quay registry certificate trust..."
	@ENDPOINT=$$(oc get quayregistry test-registry -o json | jq -r '.status.registryEndpoint'); \
	if [ "$$ENDPOINT" = "null" ] || [ -z "$$ENDPOINT" ]; then \
		echo "❌ Quay registry endpoint not ready"; \
		exit 1; \
	fi; \
	REGISTRY=$$(echo "$$ENDPOINT" | sed 's/^https:\/\///'); \
	echo "Testing connection to: $$REGISTRY"; \
	echo ""; \
	echo "📋 Checking ConfigMap configuration..."; \
	cmName="$$(oc get images.config.openshift.io/cluster -o json | jq -r '.spec.additionalTrustedCA.name // "trusted-registry-cabundles"')"; \
	if oc get -n openshift-config "cm/$$cmName" 2>/dev/null | grep -q "$${REGISTRY//:/..}"; then \
		echo "✅ Registry found in CA ConfigMap: $$cmName"; \
	else \
		echo "❌ Registry not found in CA ConfigMap"; \
		echo "Run 'make aro-quay-trust-cert' to configure trust"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "🧪 Testing HTTPS connection..."; \
	if curl -s --max-time 10 "$$ENDPOINT/health/instance" >/dev/null 2>&1; then \
		echo "✅ HTTPS connection successful"; \
	else \
		echo "⚠️  HTTPS connection failed (this may be normal if nodes haven't restarted)"; \
	fi; \
	echo ""; \
	echo "📊 Node trust status:"; \
	echo "To check if all nodes have picked up the CA bundle, run:"; \
	echo "  oc get nodes -o wide"; \
	echo "  # Check if any nodes are in NotReady state"; \
	echo ""; \
	echo "🔧 If trust verification fails:"; \
	echo "1. Ensure nodes have restarted to pick up new CA bundle"; \
	echo "2. Check: oc get mcp -o wide"; \
	echo "3. If needed, trigger node restart: oc patch mcp worker --type merge -p '{\"spec\":{\"paused\":false}}'"; \
	echo "✅ Certificate trust verification completed"

.PHONY: aro-quay-deploy-complete
aro-quay-deploy-complete:  ## Complete Quay deployment with storage, registry, and trust configuration
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP AZURE_STORAGE_ACCOUNT_NAME AZURE_STORAGE_ACCOUNT_KEY AZURE_STORAGE_CONTAINER)
	@echo "🚀 Starting complete Quay deployment on ARO..."
	@echo "Step 1/5: Deploying Quay operator and instance..."
	make aro-quay-deploy
	@echo ""
	@echo "Step 2/5: Waiting for Quay to be ready..."
	make aro-quay-wait-ready
	@echo ""
	@echo "Step 3/5: Configuring certificate trust..."
	make aro-quay-trust-cert
	@echo ""
	@echo "Step 4/5: Getting connection information..."
	make aro-quay-info
	@echo ""
	@echo "Step 5/5: Verifying trust configuration..."
	make aro-quay-verify-trust
	@echo ""
	@echo "🎉 Complete Quay deployment finished!"
	@echo "📋 Next steps:"
	@echo "1. Create admin user: make aro-quay-create-admin (requires QUAY_ADMIN_PASSWORD, QUAY_ADMIN_EMAIL)"
	@echo "2. Test login: make aro-quay-test-login"
	@echo "3. If trust verification failed, wait for nodes to restart or trigger restart manually"

.PHONY: aro-quay-status
aro-quay-status:  ## Check Quay deployment status on ARO
	@echo "📊 ARO Quay Registry Status:"
	@echo "============================"
	@echo "Operator CSV:"
	@oc get csv -n openshift-operators | grep quay-operator || echo "No operator found"
	@echo ""
	@echo "Quay Registry:"
	@oc get quayregistry -n openshift-operators || echo "No registry found"
	@echo ""
	@echo "Quay Pods:"
	@oc get pods -n openshift-operators | grep test-registry || echo "No Quay pods found"

.PHONY: aro-quay-delete
aro-quay-delete:  ## Delete Quay registry and operator from ARO
	@echo "🗑️ Deleting Quay registry from ARO..."
	oc delete quayregistry test-registry -n openshift-operators --ignore-not-found=true
	@echo "⏳ Waiting for Quay pods to terminate..."
	@timeout 120 bash -c 'while oc get pods -n openshift-operators | grep -q test-registry; do echo "Waiting..."; sleep 10; done' || echo "Timeout waiting for pods"
	@echo "🗑️ Deleting Quay operator..."
	oc delete subscription quay-operator -n openshift-operators --ignore-not-found=true
	oc delete csv -n openshift-operators -l operators.coreos.com/quay-operator.openshift-operators --ignore-not-found=true
	@echo "🧹 Cleaning up secrets and configmaps..."
	oc delete secret config-bundle-secret -n openshift-operators --ignore-not-found=true
	@echo "✅ Quay cleanup completed on ARO"

# Generic Quay Registry targets (work on any cluster with oc context)
.PHONY: quay-deploy-generic
quay-deploy-generic:  ## Deploy Quay registry on current oc context (generic)
	@echo "📦 Deploying Quay registry operator (generic)..."
	oc apply -f edge-integration-cell/quay-registry/quay-operator-subscription.yaml
	@echo "⏳ Waiting for Quay operator to be ready..."
	@timeout 300 bash -c 'until oc get csv -n openshift-operators | grep -q "quay-operator.*Succeeded"; do echo "Waiting for operator..."; sleep 10; done'
	@echo "🔧 Creating Quay configuration..."
	oc apply -f edge-integration-cell/quay-registry/quay-config-secret.yaml
	@echo "🚀 Creating Quay registry instance..."
	oc apply -f edge-integration-cell/quay-registry/quay-registry.yaml
	@echo "✅ Quay deployment initiated (generic)"

.PHONY: quay-info-generic
quay-info-generic:  ## Get Quay registry connection information (generic)
	@echo "📋 Quay Registry Information (Generic):"
	@echo "======================================="
	@ENDPOINT=$$(oc get quayregistry test-registry -o json 2>/dev/null | jq -r '.status.registryEndpoint // "Not ready"'); \
	if [ "$$ENDPOINT" != "Not ready" ]; then \
		REGISTRY=$$(echo "$$ENDPOINT" | sed 's/^https:\/\///'); \
		echo "Registry Endpoint: $$ENDPOINT"; \
		echo "Registry Host: $$REGISTRY"; \
		echo "Admin User Path: $$REGISTRY/quayadmin"; \
		echo ""; \
		echo "🔑 Create admin user with QUAY_ADMIN_PASSWORD and QUAY_ADMIN_EMAIL set"; \
		echo "🔒 Configure certificate trust as needed"; \
	else \
		echo "❌ Quay registry not ready yet"; \
	fi

.PHONY: aro-validate-test-config
aro-validate-test-config:  ## Validate test configuration before deployment
	@echo "🔍 Validating test deployment configuration..."
	@echo "=============================================="
	@PULL_SECRET_BASE64=$$(printf '%s' "$$PULL_SECRET" | tr -d '\n' | sed 's/^"//;s/"$$//' | base64 -w 0); \
	TEMP_PARAMS=$$(mktemp); \
	echo "{ \
		\"servicePrincipalClientId\": { \"value\": \"${CLIENT_ID}\" }, \
		\"servicePrincipalClientSecret\": { \"value\": \"${CLIENT_SECRET}\" }, \
		\"pullSecret\": { \"value\": \"$$PULL_SECRET_BASE64\" }, \
		\"postgresAdminPassword\": { \"value\": \"${POSTGRES_ADMIN_PASSWORD}\" } \
	}" > $$TEMP_PARAMS; \
	az deployment group validate --resource-group ${ARO_RESOURCE_GROUP} \
		--template-file bicep/aro.bicep \
		--parameters @bicep/test.parameters.json \
		--parameters @$$TEMP_PARAMS \
		--query "error" -o table; \
	rm -f $$TEMP_PARAMS
	@echo "✅ Configuration validation completed"

.PHONY: aro-what-if-test
aro-what-if-test:  ## Preview what resources will be created/modified
	$(call required-environment-variables,ARO_RESOURCE_GROUP CLIENT_ID CLIENT_SECRET TENANT_ID PULL_SECRET POSTGRES_ADMIN_PASSWORD)
	@echo "🔮 What-if analysis for test deployment..."
	@PULL_SECRET_BASE64=$$(printf '%s' "$$PULL_SECRET" | tr -d '\n' | sed 's/^"//;s/"$$//' | base64 -w 0); \
	TEMP_PARAMS=$$(mktemp); \
	echo "{ \
		\"servicePrincipalClientId\": { \"value\": \"${CLIENT_ID}\" }, \
		\"servicePrincipalClientSecret\": { \"value\": \"${CLIENT_SECRET}\" }, \
		\"pullSecret\": { \"value\": \"$$PULL_SECRET_BASE64\" }, \
		\"postgresAdminPassword\": { \"value\": \"${POSTGRES_ADMIN_PASSWORD}\" } \
	}" > $$TEMP_PARAMS; \
	az deployment group what-if --resource-group ${ARO_RESOURCE_GROUP} \
		--template-file bicep/aro.bicep \
		--parameters @bicep/test.parameters.json \
		--parameters @$$TEMP_PARAMS; \
	rm -f $$TEMP_PARAMS
