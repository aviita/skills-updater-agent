# Key Vault

**ARM Namespace:** `Microsoft.KeyVault/vaults`
**Minimum API Version:** `2023-02-01`
**Private Endpoint groupId:** `vault`
**Private DNS Zone:** `privatelink.vaultcore.azure.net`

## Minimal Private Key Vault

```hcl
resource "azapi_resource" "key_vault" {
  type      = "Microsoft.KeyVault/vaults@2023-02-01"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    properties = {
      sku = {
        family = "A"
        name   = "standard"  # or "premium" for HSM-backed keys
      }
      tenantId                     = data.azurerm_client_config.current.tenant_id
      enableRbacAuthorization      = true   # use RBAC, not access policies
      enableSoftDelete             = true
      softDeleteRetentionInDays    = 90
      enablePurgeProtection        = true
      publicNetworkAccess          = "Disabled"
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = "Deny"
        ipRules       = []
        virtualNetworkRules = []
      }
    }
    tags = var.tags
  })
}
```

## Important Properties

| Property | Required Value | Reason |
|---|---|---|
| `publicNetworkAccess` | `"Disabled"` | No public access |
| `networkAcls.defaultAction` | `"Deny"` | Belt-and-suspenders with publicNetworkAccess |
| `enableRbacAuthorization` | `true` | Access policies are legacy |
| `enableSoftDelete` | `true` | Cannot be disabled since API 2021-x |
| `enablePurgeProtection` | `true` | Required for compliance; irreversible |

## RBAC Roles (assign via azapi_resource on Microsoft.Authorization/roleAssignments)

| Role | Use case |
|---|---|
| `Key Vault Secrets User` | Read secrets (apps) |
| `Key Vault Secrets Officer` | CRUD secrets (ops) |
| `Key Vault Crypto User` | Use keys for encrypt/decrypt |
| `Key Vault Crypto Officer` | CRUD keys |
| `Key Vault Administrator` | Full control |

## Diagnostics

Send diagnostic logs to Log Analytics:

```hcl
resource "azapi_resource" "kv_diag" {
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  name      = "kv-diag"
  parent_id = azapi_resource.key_vault.id

  body = jsonencode({
    properties = {
      workspaceId = var.log_analytics_workspace_id
      logs = [
        { category = "AuditEvent";          enabled = true },
        { category = "AzurePolicyEvaluationDetails"; enabled = true }
      ]
      metrics = [{ category = "AllMetrics"; enabled = true }]
    }
  })
}
```
