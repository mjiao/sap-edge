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

@description('PostgreSQL SKU name (dev mode: Standard_B1ms)')
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL tier (dev mode: Burstable)')
param postgresTier string = 'Burstable'

@description('PostgreSQL storage size in GB')
param postgresStorageSize int = 32

@description('PostgreSQL version')
param postgresVersion string = '15'

@description('Redis cache name (auto-generated if not provided)')
param redisCacheName string = ''

@description('Redis SKU (dev mode: Basic)')
param redisSku string = 'Basic'

@description('Redis size (dev mode: C0)')
param redisSize string = 'C0'

// Variables
var postgresServerNameFinal = empty(postgresServerName) ? 'postgres-${clusterName}' : postgresServerName
var redisCacheNameFinal = empty(redisCacheName) ? 'redis-${clusterName}' : redisCacheName

// PostgreSQL Flexible Server
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = if (deployPostgres) {
  name: postgresServerNameFinal
  location: location
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
output postgresServerName string = deployPostgres && !empty(postgresServerNameFinal) ? postgresServer.name : ''
output postgresServerFqdn string = deployPostgres && !empty(postgresServerNameFinal) ? postgresServer.properties.fullyQualifiedDomainName : ''
output postgresAdminUsername string = deployPostgres ? postgresAdminUsername : ''
output postgresDatabaseName string = deployPostgres ? 'eic' : ''

output redisCacheName string = deployRedis && !empty(redisCacheNameFinal) ? redisCache.name : ''
output redisHostName string = deployRedis && !empty(redisCacheNameFinal) ? redisCache.properties.hostName : ''
output redisPort int = deployRedis && !empty(redisCacheNameFinal) ? redisCache.properties.port : 0
output redisSslPort int = deployRedis && !empty(redisCacheNameFinal) ? redisCache.properties.sslPort : 0

// Connection strings (without passwords - get from Azure portal)
output postgresConnectionString string = deployPostgres ? 'postgresql://${postgresAdminUsername}:[PASSWORD]@${postgresServerNameFinal}.postgres.database.azure.com:5432/eic?sslmode=require' : ''
output redisConnectionString string = deployRedis ? 'redis://${redisCacheNameFinal}.redis.cache.windows.net:6379' : '' 