// SPDX-FileCopyrightText: 2024 SAP edge team
// SPDX-FileContributor: Kirill Satarin (@kksat)
// SPDX-FileContributor: Manjun Jiao (@mjiao)
//
// SPDX-License-Identifier: Apache-2.0

param clusterName string
@description('The pull secret for the ARO cluster.')
@secure()
param pullSecret string
@description('The domain for the ARO cluster.')
param domain string
@description('OpenShift version for the ARO cluster')
@allowed([
    '4.14.38'
    '4.15.35'
    '4.16.39'
    '4.17.27'
    '4.18.9'
])
param version string

param servicePrincipalClientId string

@secure()
param servicePrincipalClientSecret string

param aroResourceGroup string = '${resourceGroup().name}-resources'

param vnetName string = '${resourceGroup().name}-vnet'
param masterSubnetName string = 'master'
param workerSubnetName string = 'worker'

@description('VM size for master nodes')
@allowed(['Standard_D8s_v3', 'Standard_D16s_v3'])
param masterVmSize string = 'Standard_D8s_v3'

@description('VM size for worker nodes (optimized for testing)')
@allowed(['Standard_D4s_v3', 'Standard_D8s_v3'])
param workerVmSize string = 'Standard_D4s_v3'

@description('Disk size for worker nodes in GB')
@minValue(128)
@maxValue(1024)
param workerDiskSizeGB int = 128

@description('Number of worker nodes (limited for testing)')
@minValue(3)
@maxValue(10)
param workerCount int = 3

param location string = resourceGroup().location

@description('Whether to deploy Azure Database for PostgreSQL')
param deployPostgres bool = true

@description('Whether to deploy Azure Cache for Redis')
param deployRedis bool = true

@description('PostgreSQL admin password')
@secure()
param postgresAdminPassword string = ''

// Cost optimization parameters for testing
@description('Enable auto-shutdown for cost savings (testing only)')
param enableAutoShutdown bool = true

@description('Auto-shutdown time in 24-hour format (testing only)')
param shutdownTime string = '19:00'

@description('Testing-specific tags for resource management')
param testingTags object = {
  purpose: 'testing'
  team: 'sap-edge'
  autoCleanup: 'enabled'
  maxLifetime: '7days'
  costOptimized: 'true'
}

resource aroCluster 'Microsoft.RedHatOpenShift/openShiftClusters@2023-11-22' = {
  name: clusterName
  location: location
  tags: union(testingTags, {
    clusterName: clusterName
    deployment: 'bicep'
  })
  properties: {
    clusterProfile: {
      domain: domain
      pullSecret: base64ToString(pullSecret)
      resourceGroupId: resourceId('Microsoft.Resources/resourceGroups', aroResourceGroup)
      version: version
      fipsValidatedModules: 'Disabled'
    }
    networkProfile: {
      podCidr: '10.128.0.0/14'
      serviceCidr: '172.30.0.0/16'
    }
    servicePrincipalProfile: {
      clientId: servicePrincipalClientId
      clientSecret: servicePrincipalClientSecret
    }
    masterProfile: {
      vmSize: masterVmSize
      subnetId: masterSubnet.id
      encryptionAtHost: 'Disabled'
    }
    workerProfiles: [
      {
        name: 'worker'
        vmSize: workerVmSize
        diskSizeGB: workerDiskSizeGB
        subnetId: workerSubnet.id
        count: workerCount
        encryptionAtHost: 'Disabled'
      }
    ]
    apiserverProfile: {
      visibility: 'Public'
    }
    ingressProfiles: [
      {
        name: 'default'
        visibility: 'Public'
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
}

resource masterSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: masterSubnetName
  parent: vnet
}

resource workerSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: workerSubnetName
  parent: vnet
}

// Deploy Azure services using the azure-services.bicep module
module azureServices 'azure-services.bicep' = if (deployPostgres || deployRedis) {
  name: 'azure-services-deployment'
  params: {
    clusterName: clusterName
    location: location
    deployPostgres: deployPostgres
    deployRedis: deployRedis
    postgresAdminPassword: postgresAdminPassword
  }
}

// Outputs for Azure services
output postgresServerName string = (deployPostgres || deployRedis) && deployPostgres ? azureServices.outputs.postgresServerName : ''
output postgresServerFqdn string = (deployPostgres || deployRedis) && deployPostgres ? azureServices.outputs.postgresServerFqdn : ''
output postgresAdminUsername string = (deployPostgres || deployRedis) && deployPostgres ? azureServices.outputs.postgresAdminUsername : ''
output postgresDatabaseName string = (deployPostgres || deployRedis) && deployPostgres ? azureServices.outputs.postgresDatabaseName : ''

output redisCacheName string = (deployPostgres || deployRedis) && deployRedis ? azureServices.outputs.redisCacheName : ''
output redisHostName string = (deployPostgres || deployRedis) && deployRedis ? azureServices.outputs.redisHostName : ''
output redisPort int = (deployPostgres || deployRedis) && deployRedis ? azureServices.outputs.redisPort : 0
output redisSslPort int = (deployPostgres || deployRedis) && deployRedis ? azureServices.outputs.redisSslPort : 0

// Connection strings
output postgresConnectionString string = (deployPostgres || deployRedis) && deployPostgres ? azureServices.outputs.postgresConnectionString : ''
output redisConnectionString string = (deployPostgres || deployRedis) && deployRedis ? azureServices.outputs.redisConnectionString : ''

// Enhanced testing-focused outputs
@description('Quick connection info for testing and debugging')
output quickConnectionInfo object = {
  cluster: {
    name: clusterName
    apiServerUrl: aroCluster.properties.apiserverProfile.url
    consoleUrl: aroCluster.properties.consoleProfile.url
    version: version
    workerCount: workerCount
    domain: domain
  }
  commands: {
    getKubeconfig: 'az aro get-admin-kubeconfig --name ${clusterName} --resource-group ${resourceGroup().name} --file kubeconfig'
    getCredentials: 'az aro list-credentials --name ${clusterName} --resource-group ${resourceGroup().name}'
    ocLogin: 'oc login ${aroCluster.properties.apiserverProfile.url}'
  }
  services: {
    postgres: (deployPostgres || deployRedis) && deployPostgres ? {
      serverName: azureServices.outputs.postgresServerName
      serverFqdn: azureServices.outputs.postgresServerFqdn
      databaseName: azureServices.outputs.postgresDatabaseName
      adminUsername: azureServices.outputs.postgresAdminUsername
      connectCommand: 'az postgres flexible-server connect --name ${azureServices.outputs.postgresServerName} --admin-user ${azureServices.outputs.postgresAdminUsername} --database ${azureServices.outputs.postgresDatabaseName}'
    } : null
    redis: (deployPostgres || deployRedis) && deployRedis ? {
      cacheName: azureServices.outputs.redisCacheName
      hostName: azureServices.outputs.redisHostName
      port: azureServices.outputs.redisPort
      sslPort: azureServices.outputs.redisSslPort
      getKeysCommand: 'az redis list-keys --name ${azureServices.outputs.redisCacheName} --resource-group ${resourceGroup().name}'
    } : null
  }
  testing: {
    tags: testingTags
    autoShutdown: enableAutoShutdown
    shutdownTime: shutdownTime
    estimatedMonthlyCost: 'Check Azure Cost Management for current costs'
    cleanupCommand: 'az group delete --name ${resourceGroup().name} --yes --no-wait'
  }
}

@description('ARO cluster resource ID for additional operations')
output aroClusterId string = aroCluster.id

@description('ARO cluster API server URL')
output apiServerUrl string = aroCluster.properties.apiserverProfile.url

@description('ARO cluster console URL')
output consoleUrl string = aroCluster.properties.consoleProfile.url

