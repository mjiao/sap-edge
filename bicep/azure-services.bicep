// SPDX-FileCopyrightText: 2025 SAP edge team
// SPDX-FileContributor: Manjun Jiao (@mjiao)
//
// SPDX-License-Identifier: Apache-2.0

@description('The name of the ARO cluster (used for naming the services)')
param clusterName string

@description('The location for the services')
param location string = resourceGroup().location

@description('VNet ID for VNet integration')
param vnetId string

@description('Postgres subnet ID for VNet integration')
param postgresSubnetId string

@description('Redis subnet ID for VNet integration')
param redisSubnetId string

@description('Whether to deploy PostgreSQL Flexible Server')
param deployPostgres bool = true

@description('Whether to deploy Redis Cache')
param deployRedis bool = true

@description('PostgreSQL server name (auto-generated if not provided)')
param postgresServerName string = ''

@description('PostgreSQL admin username')
param postgresAdminUsername string = 'eicadmin'

@description('PostgreSQL admin password')
@secure()
param postgresAdminPassword string

@description('PostgreSQL SKU name (cost-optimized for testing)')
@allowed(['Standard_B1ms', 'Standard_B2s', 'Standard_D2s_v3'])
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL tier (cost-optimized for testing)')
@allowed(['Burstable', 'GeneralPurpose'])
param postgresTier string = 'Burstable'

@description('PostgreSQL storage size in GB (minimal for testing)')
@minValue(32)
@maxValue(128)
param postgresStorageSize int = 32

@description('PostgreSQL version')
@allowed(['13', '14', '15', '16'])
param postgresVersion string = '15'

@description('Whether to deploy Quay storage')
param deployQuay bool = true

@description('Redis cache name (auto-generated if not provided)')
param redisCacheName string = ''

@description('Quay storage account name (auto-generated if not provided)')
param quayStorageAccountName string = ''

@description('Redis SKU (cost-optimized for testing)')
@allowed(['Basic', 'Standard', 'Premium'])
param redisSku string = 'Basic'

@description('Redis family')
@allowed(['C', 'P'])
param redisFamily string = 'C'

@description('Redis capacity')
@minValue(0)
@maxValue(6)
param redisCapacity int = 0

@description('Testing-specific tags for resource management')
param testingTags object = {
  purpose: 'testing'
  team: 'sap-edge'
  autoCleanup: 'enabled'
  maxLifetime: '7days'
  costOptimized: 'true'
}

// Variables
var postgresServerNameFinal = empty(postgresServerName) ? 'postgres-${clusterName}' : postgresServerName
var redisCacheNameFinal = empty(redisCacheName) ? 'redis-${clusterName}' : redisCacheName
var quayStorageAccountNameFinal = empty(quayStorageAccountName) ? 'quay${uniqueString(resourceGroup().id, clusterName)}' : quayStorageAccountName

// Private DNS Zone for PostgreSQL
resource postgresDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPostgres) {
  name: '${postgresServerNameFinal}.private.postgres.database.azure.com'
  location: 'global'
  tags: union(testingTags, {
    service: 'postgresql-dns'
    clusterName: clusterName
  })
}

resource postgresDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPostgres) {
  name: '${postgresServerNameFinal}-vnet-link'
  parent: postgresDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// PostgreSQL Flexible Server with VNet integration
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = if (deployPostgres) {
  name: postgresServerNameFinal
  location: location
  tags: union(testingTags, {
    service: 'postgresql'
    clusterName: clusterName
  })
  sku: {
    name: postgresSkuName
    tier: postgresTier
  }
  properties: {
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    version: postgresVersion
    storage: {
      storageSizeGB: postgresStorageSize
    }
    network: {
      delegatedSubnetResourceId: postgresSubnetId
      privateDnsZoneArmResourceId: postgresDnsZone.id
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    maintenanceWindow: {
      customWindow: 'Disabled'
      dayOfWeek: 0
      startHour: 2
      startMinute: 0
    }
  }
  dependsOn: [
    postgresDnsZoneVnetLink
  ]
}

// PostgreSQL Database
resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = if (deployPostgres) {
  name: 'eic'
  parent: postgresServer
  properties: {
    charset: 'utf8'
    collation: 'en_US.utf8'
  }
}

// Redis Cache with private endpoint
resource redisCache 'Microsoft.Cache/redis@2023-08-01' = if (deployRedis) {
  name: redisCacheNameFinal
  location: location
  tags: union(testingTags, {
    service: 'redis'
    clusterName: clusterName
  })
  properties: {
    sku: {
      name: redisSku
      family: redisFamily
      capacity: redisCapacity
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

// Private DNS Zone for Redis
resource redisDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployRedis) {
  name: 'privatelink.redis.cache.windows.net'
  location: 'global'
  tags: union(testingTags, {
    service: 'redis-dns'
    clusterName: clusterName
  })
}

resource redisDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployRedis) {
  name: '${redisCacheNameFinal}-vnet-link'
  parent: redisDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private Endpoint for Redis
resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = if (deployRedis) {
  name: '${redisCacheNameFinal}-pe'
  location: location
  tags: union(testingTags, {
    service: 'redis-private-endpoint'
    clusterName: clusterName
  })
  properties: {
    subnet: {
      id: redisSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${redisCacheNameFinal}-connection'
        properties: {
          privateLinkServiceId: redisCache.id
          groupIds: [
            'redisCache'
          ]
        }
      }
    ]
  }
}

// DNS Zone Group for Private Endpoint
resource redisDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (deployRedis) {
  name: 'default'
  parent: redisPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'redis-config'
        properties: {
          privateDnsZoneId: redisDnsZone.id
        }
      }
    ]
  }
}

//##########################################
// Quay Container Registry Storage
//##########################################

// Storage Account for Quay
resource quayStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (deployQuay) {
  name: quayStorageAccountNameFinal
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: union(testingTags, {
    service: 'quay'
    clusterName: clusterName
  })
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Blob Service for Quay
resource quayBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = if (deployQuay) {
  name: 'default'
  parent: quayStorageAccount
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Blob Container for Quay Registry
resource quayBlobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (deployQuay) {
  name: 'quay-registry'
  parent: quayBlobService
  properties: {
    publicAccess: 'None'
  }
}

// Outputs
output postgresServerName string = deployPostgres ? postgresServer.name : ''
output postgresServerFqdn string = deployPostgres ? postgresServer.properties.fullyQualifiedDomainName : ''
output postgresAdminUsername string = deployPostgres ? postgresAdminUsername : ''
output postgresDatabaseName string = deployPostgres ? 'eic' : ''

output redisCacheName string = deployRedis ? redisCache.name : ''
output redisHostName string = deployRedis ? redisCache.properties.hostName : ''
output redisPort int = deployRedis ? redisCache.properties.port : 0
output redisSslPort int = deployRedis ? redisCache.properties.sslPort : 0

// Quay Storage outputs
output quayStorageAccountName string = deployQuay ? quayStorageAccount.name : ''
output quayStorageAccountKey string = deployQuay ? quayStorageAccount.listKeys().keys[0].value : ''
output quayContainerName string = deployQuay ? 'quay-registry' : ''

// Connection strings (without passwords - get from Azure portal)
output postgresConnectionString string = deployPostgres ? 'postgresql://${postgresAdminUsername}:[PASSWORD]@${postgresServerNameFinal}.postgres.database.azure.com:5432/eic?sslmode=require' : ''
output redisConnectionString string = deployRedis ? 'redis://${redisCacheNameFinal}.redis.cache.windows.net:6379' : '' 