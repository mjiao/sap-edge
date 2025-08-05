# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Kirill Satarin (@kksat)
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

ARO_RESOURCE_GROUP?=aro-sapeic
ARO_LOCATION?=northeurope

ARO_CLUSTER_NAME?=aro-sapeic
ARO_DOMAIN?=saponrhel.org
ARO_VERSION?=4.15.35

# Azure services configuration
DEPLOY_POSTGRES?=true
DEPLOY_REDIS?=true
POSTGRES_ADMIN_PASSWORD?=

.PHONY: aro-deploy
.ONESHELL:
aro-deploy: domain-zone-exists network-deploy  ## Deploy ARO
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME ARO_DOMAIN ARO_VERSION CLIENT_ID CLIENT_SECRET)
	@PULL_SECRET_BASE64=$$(printf '%s' "$$PULL_SECRET" | tr -d '\n' | sed 's/^"//;s/"$$//' | base64 -w 0)
	@az deployment group create --resource-group ${ARO_RESOURCE_GROUP} \
		--template-file bicep/aro.bicep \
		--parameters \
		clusterName="${ARO_CLUSTER_NAME}" \
		pullSecret="$$PULL_SECRET_BASE64" \
		domain="${ARO_CLUSTER_NAME}.${ARO_DOMAIN}" \
		version="${ARO_VERSION}" \
		servicePrincipalClientId="${CLIENT_ID}" \
		servicePrincipalClientSecret="${CLIENT_SECRET}" \
		deployPostgres="${DEPLOY_POSTGRES}" \
		deployRedis="${DEPLOY_REDIS}" \
		postgresAdminPassword="${POSTGRES_ADMIN_PASSWORD}"

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
	az login --service-principal -u "${CLIENT_ID}" -p "${CLIENT_SECRET}" --tenant "${TENANT_ID}"

.PHONY: azure-set-subscription
azure-set-subscription:  ## Set Azure subscription to current account
	az account set --subscription "$(az account show --query id -o tsv)"

.PHONY: aro-cluster-status
aro-cluster-status:  ## Get ARO cluster provisioning state
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	@az aro show --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" --query "provisioningState" -o tsv

.PHONY: aro-cluster-exists
aro-cluster-exists:  ## Check if ARO cluster exists
	$(call required-environment-variables,ARO_CLUSTER_NAME ARO_RESOURCE_GROUP)
	@az aro show --name "${ARO_CLUSTER_NAME}" --resource-group "${ARO_RESOURCE_GROUP}" >/dev/null 2>&1 && echo "true" || echo "false"

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



aro-url:  ## Get ARO URL
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME)
	@az aro show --name ${ARO_CLUSTER_NAME} --resource-group ${ARO_RESOURCE_GROUP} --query "apiserverProfile.url" -o tsv

aro-services-info:  ## Get Azure services information
	$(call required-environment-variables,ARO_RESOURCE_GROUP)
	@echo "=== Azure Services Information ==="
	@az deployment group show --resource-group ${ARO_RESOURCE_GROUP} --name aro-deploy --query "properties.outputs" -o json | jq -r '
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



.PHONY: azure-services-deploy
azure-services-deploy:  ## Deploy Azure services only (public access)
	$(call required-environment-variables,ARO_RESOURCE_GROUP ARO_CLUSTER_NAME POSTGRES_ADMIN_PASSWORD)
	@az deployment group create --resource-group ${ARO_RESOURCE_GROUP} \
		--template-file bicep/azure-services.bicep \
		--parameters \
		clusterName="${ARO_CLUSTER_NAME}" \
		location="${ARO_LOCATION}" \
		deployPostgres="${DEPLOY_POSTGRES}" \
		deployRedis="${DEPLOY_REDIS}" \
		postgresAdminPassword="${POSTGRES_ADMIN_PASSWORD}"
