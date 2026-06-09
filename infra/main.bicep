// ============================================================================
//  infra/main.bicep — Azure ML workspace + all required supporting resources
// ============================================================================
//  Provisions everything PHASE 1 of GETTING_STARTED.md does by hand:
//    • Storage account   (required by AML)
//    • Key Vault         (required by AML)
//    • Application Insights + Log Analytics  (required by AML)
//    • Azure ML workspace
//    • Compute cluster   (cpu-cluster, min 0 / max 2 — costs nothing when idle)
//
//  Deployed by azure-infra-pipeline.yml (trigger: none — manual-only).
//  Safe to re-run: Bicep deployments are idempotent (update-or-create).
//  Docs: https://learn.microsoft.com/azure/machine-learning/how-to-create-workspace-template
// ============================================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the Azure ML workspace.')
param workspaceName string = 'aml-iris-ws'

@description('Name of the compute cluster inside the workspace.')
param computeClusterName string = 'cpu-cluster'

// Unique 13-char hash derived from the resource group ID.
// Guarantees globally unique Storage and Key Vault names without manual input.
var suffix             = uniqueString(resourceGroup().id)
var storageAccountName = 'st${suffix}'          // 2 + 13 = 15 chars  (limit: 3–24)
var keyVaultName       = 'kv-${suffix}'         // 3 + 13 = 16 chars  (limit: 3–24)
var appInsightsName    = 'appi-${workspaceName}'
var logAnalyticsName   = 'log-${workspaceName}'

// ── Log Analytics Workspace (backing store for Application Insights) ─────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Application Insights ─────────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ── Storage Account ──────────────────────────────────────────────────────────
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// ── Key Vault ────────────────────────────────────────────────────────────────
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// ── Azure ML Workspace ───────────────────────────────────────────────────────
resource amlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: workspaceName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    storageAccount: storage.id
    keyVault: keyVault.id
    applicationInsights: appInsights.id
  }
}

// ── Compute cluster (scales to 0 when idle — no cost between training runs) ──
resource computeCluster 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  parent: amlWorkspace
  name: computeClusterName
  location: location
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: 'Standard_E2ds_v4'
      scaleSettings: {
        minNodeCount: 0
        maxNodeCount: 2
        nodeIdleTimeBeforeScaleDown: 'PT120S'
      }
    }
  }
}

// ── Outputs — printed in the pipeline log after a successful deploy ───────────
// Copy these values into the iris-mlops-vars variable group (Phase 2, Step 4).
output workspaceName string      = amlWorkspace.name
output resourceGroupName string  = resourceGroup().name
output location string           = amlWorkspace.location
output computeClusterName string = computeCluster.name
