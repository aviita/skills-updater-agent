# Storage Accounts

**ARM Namespace:** `Microsoft.Storage/storageAccounts`
**Minimum API Version:** `2023-01-01`
**Private Endpoint groupIds:** `blob`, `file`, `queue`, `table` (one PE per subresource needed)
**Private DNS Zones:** See `private-endpoints.md`

## Minimal Private Storage Account

```hcl
resource "azapi_resource" "storage" {
  type      = "Microsoft.Storage/storageAccounts@2023-01-01"
  name      = var.name   # 3-24 chars, lowercase alphanumeric only
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }  # or Standard_ZRS for zone-redundant
    properties = {
      publicNetworkAccess             = "Disabled"
      allowBlobPublicAccess           = false
      allowSharedKeyAccess            = false   # force Azure AD auth only
      minimumTlsVersion               = "TLS1_2"
      supportsHttpsTrafficOnly        = true
      defaultToOAuthAuthentication    = true
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
| `allowBlobPublicAccess` | `false` | No anonymous blob access |
| `allowSharedKeyAccess` | `false` | Force Entra ID auth; disable SAS keys |
| `minimumTlsVersion` | `"TLS1_2"` | Security baseline |
| `networkAcls.defaultAction` | `"Deny"` | Belt-and-suspenders |

> **Note:** `allowSharedKeyAccess = false` breaks some legacy tools that rely on connection strings.
> If a workload requires SAS tokens, document the exception in an ADR before enabling.

## Blob Service Configuration

```hcl
resource "azapi_resource" "blob_service" {
  type      = "Microsoft.Storage/storageAccounts/blobServices@2023-01-01"
  name      = "default"
  parent_id = azapi_resource.storage.id

  body = jsonencode({
    properties = {
      deleteRetentionPolicy = {
        enabled = true
        days    = 30
      }
      containerDeleteRetentionPolicy = {
        enabled = true
        days    = 30
      }
      isVersioningEnabled = true
    }
  })
}
```

## Multiple Private Endpoints

If the storage account serves both blob and file traffic, create separate PEs:

```hcl
# One PE per subresource — blob
resource "azapi_resource" "pe_blob" {
  # ... groupIds = ["blob"]
}

# One PE per subresource — file
resource "azapi_resource" "pe_file" {
  # ... groupIds = ["file"]
}
```

Each requires its own DNS zone group entry (or separate zones per subresource type).
