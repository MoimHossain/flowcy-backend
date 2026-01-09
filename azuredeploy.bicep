@description('Azure region for all resources. Defaults to the resource group location when not specified.')
param location string = resourceGroup().location

@minLength(3)
@description('Prefix used for resource names (letters, numbers, and hyphens).')
param namePrefix string = 'flowcy'

@minLength(3)
@description('Globally unique name for the Azure Cosmos DB account (lowercase letters and numbers only).')
param cosmosAccountName string = toLower(substring(replace('${namePrefix}${uniqueString(resourceGroup().id)}', '-', ''), 0, 44))

@description('Cosmos DB database id used by the Flowcy services.')
param cosmosDatabaseName string = 'stellaris'

@minValue(400)
@description('Provisioned RU/s for the Cosmos DB database. Increase for larger deployments.')
param cosmosDatabaseThroughput int = 400

@description('Azure DevOps organization name that Flowcy will manage.')
param devOpsOrgName string

@description('Container image for the Flowcy Web API.')
param webImage string = 'moimhossain/azdo-control-panel:v2'

@description('Container image for the Flowcy daemon processor.')
param daemonImage string = 'moimhossain/azdo-control-panel-daemon:v2'

@secure()
@description('Azure DevOps PAT that the Web API will use for elevated calls.')
param webPatSecret string

@secure()
@description('Azure DevOps PAT that the daemon will use. Reuse the Web PAT if desired.')
param daemonPatSecret string

@minValue(0)
@description('Minimum replica count for the Web API container app.')
param webReplicaMin int = 1

@minValue(1)
@description('Maximum replica count for the Web API container app.')
param webReplicaMax int = 3

@minValue(0)
@description('Minimum replica count for the daemon container app.')
param daemonReplicaMin int = 1

@minValue(1)
@description('Maximum replica count for the daemon container app.')
param daemonReplicaMax int = 1

@description('CPU cores assigned to the Web API container (provide decimal values as strings, e.g., 0.5).')
param webContainerCpu string = '1'

@description('Memory assigned to the Web API container (e.g., 1Gi, 2Gi).')
param webContainerMemory string = '2Gi'

@description('CPU cores assigned to the daemon container (provide decimal values as strings, e.g., 0.5).')
param daemonContainerCpu string = '0.5'

@description('Memory assigned to the daemon container (e.g., 0.5Gi, 1Gi).')
param daemonContainerMemory string = '1Gi'

@description('Port exposed by the Web API container for HTTP ingress.')
param webContainerPort int = 8080

var logAnalyticsWorkspaceName = '${namePrefix}-law'
var containerAppsEnvironmentName = '${namePrefix}-cae'
var webContainerAppName = '${namePrefix}-api'
var daemonContainerAppName = '${namePrefix}-daemon'
var logAnalyticsApiVersion = '2022-10-01'
var cosmosApiVersion = '2023-04-15'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: listKeys(logAnalytics.id, logAnalyticsApiVersion).primarySharedKey
      }
    }
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    publicNetworkAccess: 'Enabled'
    enableFreeTier: false
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  name: cosmosDatabaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
    options: {
      throughput: cosmosDatabaseThroughput
    }
  }
}
var cosmosPrimaryKey = listKeys(cosmosAccount.id, cosmosApiVersion).primaryMasterKey
var cosmosConnectionString = 'AccountEndpoint=${cosmosAccount.properties.documentEndpoint};AccountKey=${cosmosPrimaryKey};'
var webCpu = json(webContainerCpu)
var daemonCpu = json(daemonContainerCpu)

resource webApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: webContainerAppName
  location: location
  properties: {
    managedEnvironmentId: containerEnvironment.id
    configuration: {
      ingress: {
        external: true
        transport: 'auto'
        targetPort: webContainerPort
      }
      secrets: [
        {
          name: 'cosmos-conn'
          value: cosmosConnectionString
        }
        {
          name: 'devops-pat'
          value: webPatSecret
        }
      ]
      registries: []
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'web'
          image: webImage
          resources: {
            cpu: webCpu
            memory: webContainerMemory
          }
          env: [
            {
              name: 'AZURE_COSMOS_CONNECTIONSTRING'
              secretRef: 'cosmos-conn'
            }
            {
              name: 'AZURE_COSMOS_DATABASEID'
              value: cosmosDatabaseName
            }
            {
              name: 'AZURE_DEVOPS_ORGNAME'
              value: devOpsOrgName
            }
            {
              name: 'AZURE_DEVOPS_USE_PAT'
              value: 'true'
            }
            {
              name: 'AZURE_DEVOPS_USE_MANAGED_IDENTITY'
              value: 'false'
            }
            {
              name: 'AZURE_DEVOPS_USE_SERVICE_PRINCIPAL'
              value: 'false'
            }
            {
              name: 'AZURE_DEVOPS_PAT'
              secretRef: 'devops-pat'
            }
          ]
        }
      ]
      scale: {
        minReplicas: webReplicaMin
        maxReplicas: webReplicaMax
      }
    }
  }
  dependsOn: [
    cosmosDatabase
  ]
}

resource daemonApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: daemonContainerAppName
  location: location
  properties: {
    managedEnvironmentId: containerEnvironment.id
    configuration: {
      secrets: [
        {
          name: 'cosmos-conn'
          value: cosmosConnectionString
        }
        {
          name: 'daemon-devops-pat'
          value: daemonPatSecret
        }
      ]
      registries: []
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'daemon'
          image: daemonImage
          resources: {
            cpu: daemonCpu
            memory: daemonContainerMemory
          }
          env: [
            {
              name: 'AZURE_COSMOS_CONNECTIONSTRING'
              secretRef: 'cosmos-conn'
            }
            {
              name: 'AZURE_COSMOS_DATABASEID'
              value: cosmosDatabaseName
            }
            {
              name: 'AZURE_DEVOPS_ORGNAME'
              value: devOpsOrgName
            }
            {
              name: 'AZURE_DEVOPS_USE_PAT'
              value: 'true'
            }
            {
              name: 'AZURE_DEVOPS_USE_MANAGED_IDENTITY'
              value: 'false'
            }
            {
              name: 'AZURE_DEVOPS_USE_SERVICE_PRINCIPAL'
              value: 'false'
            }
            {
              name: 'AZURE_DEVOPS_PAT'
              secretRef: 'daemon-devops-pat'
            }
          ]
        }
      ]
      scale: {
        minReplicas: daemonReplicaMin
        maxReplicas: daemonReplicaMax
      }
    }
  }
  dependsOn: [
    cosmosDatabase
  ]
}

output webAppFqdn string = webApp.properties.configuration.ingress.fqdn
output daemonAppName string = daemonApp.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
