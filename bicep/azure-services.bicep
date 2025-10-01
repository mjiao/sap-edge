// SPDX-FileCopyrightText: 2025 SAP edge team
// SPDX-FileContributor: Manjun Jiao (@mjiao)
//
// SPDX-License-Identifier: Apache-2.0

@description('The name of the ARO cluster (used for naming the services)')
param clusterName string

@description('The location for the services')
param location string = resourceGroup().location

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

@description('Redis cache name (auto-generated if not provided)')
param redisCacheName string = ''

@description('Redis SKU (cost-optimized for testing)')
@allowed(['Basic', 'Standard'])
param redisSku string = 'Basic'

@description('Redis size (minimal for testing)')
@allowed(['C0', 'C1', 'C2'])
param redisSize string = 'C0'

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

// PostgreSQL Flexible Server
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
      delegatedSubnetResourceId: ''
      privateDnsZoneArmResourceId: ''
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

// Redis Cache
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
      family: 'C'
      capacity: int(replace(redisSize, 'C', ''))
    }
    enableNonSslPort: true
    minimumTlsVersion: '1.2'
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

// Connection strings (without passwords - get from Azure portal)
output postgresConnectionString string = deployPostgres ? 'postgresql://${postgresAdminUsername}:[PASSWORD]@${postgresServerNameFinal}.postgres.database.azure.com:5432/eic?sslmode=require' : ''
output redisConnectionString string = deployRedis ? 'redis://${redisCacheNameFinal}.redis.cache.windows.net:6379' : '' 