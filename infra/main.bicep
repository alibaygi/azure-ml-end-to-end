// ============================================================================
//  infra/main.bicep — Azure ML workspace + all required supporting resources
// ============================================================================
//  Provisions everything PHASE 1 of GETTING_STARTED.md does by hand:
//    • Storage account   (required by AML)
//    • Key Vault         (required by AML) — RBAC-authorized
//    • Application Insights + Log Analytics  (required by AML)
//    • Azure ML workspace (system-assigned managed identity)
//    • Compute cluster   (cpu-cluster, min 0 / max 2 — costs nothing when idle)
//    • RBAC role assignments granting the workspace identity access to KV + storage
//      (the "credential-less" pattern — no keys stored anywhere)
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

@description('''Assign RBAC roles (Key Vault Administrator + Storage Blob Data Contributor)
to the workspace managed identity. Requires the deploying principal to have Owner or
User Access Administrator. Set to false if your service connection is only Contributor —
the workspace still deploys, you just grant these roles manually later.''')
param assignRbacRoles bool = true

// Tags applied to every resource — standard for cost attribution + governance,
// which matters in MLOps where compute and endpoints are the real cost drivers.
var tags = {
  project: 'iris-mlops'
  environment: 'dev'
  managedBy: 'bicep'
}

// Unique 13-char hash derived from the resource group ID.
// Guarantees globally unique Storage and Key Vault names without manual input.
var suffix             = uniqueString(resourceGroup().id)
var storageAccountName = 'st${suffix}'          // 2 + 13 = 15 chars  (limit: 3–24)
var keyVaultName       = 'kv-${suffix}'         // 3 + 13 = 16 chars  (limit: 3–24)
var appInsightsName    = 'appi-${workspaceName}'
var logAnalyticsName   = 'log-${workspaceName}'

// Built-in role definition IDs (stable GUIDs across all Azure tenants).
var keyVaultAdministratorRoleId   = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
var storageBlobDataContributorId  = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ── Log Analytics Workspace (backing store for Application Insights) ─────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Application Insights ─────────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
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
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// ── Key Vault (RBAC-authorized — the current best practice over access policies) ──
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    // RBAC for data-plane access instead of the legacy accessPolicies model.
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// ── Azure ML Workspace ───────────────────────────────────────────────────────
resource amlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: workspaceName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    storageAccount: storage.id
    keyVault: keyVault.id
    applicationInsights: appInsights.id
  }
}

// ── Compute cluster (scales to 0 when idle — no cost between training runs) ──
//  This is the SINGLE source of truth for the cluster. azure-pipelines.yml no
//  longer creates it — it assumes infra provisioned it (fails loudly if not).
resource computeCluster 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  parent: amlWorkspace
  name: computeClusterName
  location: location
  tags: tags
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

// ── RBAC: let the workspace identity read/write KV secrets (no stored keys) ──
resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignRbacRoles) {
  scope: keyVault
  name: guid(keyVault.id, amlWorkspace.id, keyVaultAdministratorRoleId)
  properties: {
    principalId: amlWorkspace.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministratorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// ── RBAC: let the workspace identity read/write blob data (credential-less datastore) ──
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignRbacRoles) {
  scope: storage
  name: guid(storage.id, amlWorkspace.id, storageBlobDataContributorId)
  properties: {
    principalId: amlWorkspace.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorId)
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs — printed in the pipeline log after a successful deploy ───────────
// Copy these values into the iris-mlops-vars variable group (Phase 2, Step 4).
output workspaceName string      = amlWorkspace.name
output resourceGroupName string  = resourceGroup().name
output location string           = amlWorkspace.location
output computeClusterName string = computeCluster.name
