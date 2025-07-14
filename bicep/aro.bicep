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
@allowed([
    '4.16.39'
    '4.15.35'
    '4.14.38'
    '4.17.27'
])
param version string
param servicePrincipalClientId string
@secure()
param servicePrincipalClientSecret string
param aroResourceGroup string = '${resourceGroup().name}-resources'

param vnetName string = '${resourceGroup().name}-vnet'
param masterSubnetName string = 'master'
param workerSubnetName string = 'worker'
param masterVmSize string = 'Standard_D8s_v3'
param workerVmSize string = 'Standard_D4s_v3'
param workerDiskSizeGB int = 128
@minValue(3)
param workerCount int = 3

param location string = resourceGroup().location

@description('Whether to deploy Azure Database for PostgreSQL')
param deployPostgres bool = true

@description('Whether to deploy Azure Cache for Redis')
param deployRedis bool = true

@description('PostgreSQL admin password')
@secure()
param postgresAdminPassword string = ''

resource aroCluster 'Microsoft.RedHatOpenShift/openShiftClusters@2023-11-22' = {
  name: clusterName
  location: location
  properties: {
    clusterProfile: {
      domain: domain
      pullSecret: base64ToString(pullSecret)
      resourceGroupId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${aroResourceGroup}'
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
output postgresServerName string = deployPostgres ? azureServices.outputs.postgresServerName : ''
output postgresServerFqdn string = deployPostgres ? azureServices.outputs.postgresServerFqdn : ''
output postgresAdminUsername string = deployPostgres ? azureServices.outputs.postgresAdminUsername : ''
output postgresDatabaseName string = deployPostgres ? azureServices.outputs.postgresDatabaseName : ''

output redisCacheName string = deployRedis ? azureServices.outputs.redisCacheName : ''
output redisHostName string = deployRedis ? azureServices.outputs.redisHostName : ''
output redisPort int = deployRedis ? azureServices.outputs.redisPort : 0
output redisSslPort int = deployRedis ? azureServices.outputs.redisSslPort : 0

// Connection strings
output postgresConnectionString string = deployPostgres ? azureServices.outputs.postgresConnectionString : ''
output redisConnectionString string = deployRedis ? azureServices.outputs.redisConnectionString : ''

