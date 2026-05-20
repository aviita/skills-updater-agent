# Cosmos DB

**ARM Namespace:** `Microsoft.DocumentDB/databaseAccounts`
**Minimum API Version:** `2023-04-15`
**Private Endpoint groupId:** `Sql` (for SQL API), `MongoDB`, `Table` — see `private-endpoints.md`
**Private DNS Zone:** `privatelink.documents.azure.com` (SQL API)

---

## Private Cosmos DB Account (SQL API)

```hcl
resource "azapi_resource" "cosmos" {
  type      = "Microsoft.DocumentDB/databaseAccounts@2023-04-15"
  name      = var.name   # 3-44 chars, lowercase alphanumeric and hyphens
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    kind = "GlobalDocumentDB"   # SQL API; use "MongoDB" for Mongo API
    properties = {
      databaseAccountOfferType   = "Standard"
      publicNetworkAccess        = "Disabled"
      disableLocalAuth           = true    # force Entra ID auth; disable keys
      enableAutomaticFailover    = false   # set true if multi-region
      enableMultipleWriteLocations = false
      consistencyPolicy = {
        defaultConsistencyLevel = "Session"
      }
      locations = [{
        locationName     = var.location
        failoverPriority = 0
        isZoneRedundant  = false   # set true for production
      }]
      networkAclBypass           = "None"
      isVirtualNetworkFilterEnabled = false  # use Private Endpoint instead
      ipRules                    = []
      virtualNetworkRules        = []
      backupPolicy = {
        type = "Periodic"
        periodicModeProperties = {
          backupIntervalInMinutes       = 240
          backupRetentionIntervalInHours = 8
          backupStorageRedundancy       = "Local"  # or "Geo" for production
        }
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
| `disableLocalAuth` | `true` | Force Entra ID; disable primary/secondary keys |
| `isVirtualNetworkFilterEnabled` | `false` | Use PE instead of VNet service endpoints |
| `ipRules` | `[]` | No IP allowlist needed with PE |

> **`disableLocalAuth = true`** means connection strings with account keys stop working.
> All access must go through Entra ID RBAC. Ensure managed identities are granted
> `Cosmos DB Built-in Data Contributor` or equivalent before enabling.

## Cosmos DB RBAC Roles

| Role Name | Role Definition ID (suffix) | Use Case |
|---|---|---|
| Cosmos DB Built-in Data Reader | `00000000-0000-0000-0000-000000000001` | Read-only |
| Cosmos DB Built-in Data Contributor | `00000000-0000-0000-0000-000000000002` | Read/write |

Assign via `Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15`:

```hcl
resource "azapi_resource" "cosmos_role_assignment" {
  type      = "Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15"
  name      = uuidv5("url", "${azapi_resource.cosmos.id}/${var.principal_id}")
  parent_id = azapi_resource.cosmos.id

  body = jsonencode({
    properties = {
      roleDefinitionId = "${azapi_resource.cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
      principalId      = var.principal_id
      scope            = azapi_resource.cosmos.id
    }
  })
}
```

## SQL Database and Container

```hcl
resource "azapi_resource" "cosmos_db" {
  type      = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15"
  name      = var.database_name
  parent_id = azapi_resource.cosmos.id

  body = jsonencode({
    properties = {
      resource = { id = var.database_name }
      options  = { autoscaleSettings = { maxThroughput = 4000 } }
    }
  })
}

resource "azapi_resource" "cosmos_container" {
  type      = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15"
  name      = var.container_name
  parent_id = azapi_resource.cosmos_db.id

  body = jsonencode({
    properties = {
      resource = {
        id           = var.container_name
        partitionKey = { paths = ["/partitionKey"]; kind = "Hash" }
        defaultTtl   = -1   # -1 = no TTL; set positive int for auto-expiry in seconds
      }
    }
  })
}
```
