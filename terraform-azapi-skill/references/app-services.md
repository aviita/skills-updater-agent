# App Services & Function Apps

**ARM Namespaces:**
- `Microsoft.Web/serverfarms` — App Service Plan
- `Microsoft.Web/sites` — Web App or Function App
- `Microsoft.Web/sites/config` — App settings, VNet integration

**Minimum API Version:** `2022-09-01`
**Private Endpoint groupId:** `sites`
**Private DNS Zone:** `privatelink.azurewebsites.net`

> Private access for App Services requires **both**:
> 1. **Private Endpoint** — for inbound traffic (replaces public hostname resolution)
> 2. **VNet Integration** — for outbound traffic to private resources (Key Vault, Storage, DB)

---

## App Service Plan

```hcl
resource "azapi_resource" "asp" {
  type      = "Microsoft.Web/serverfarms@2022-09-01"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    kind = "linux"   # or "windows"
    sku  = {
      name     = "P1v3"   # minimum for VNet integration; B-tier does NOT support it
      tier     = "PremiumV3"
      capacity = 1
    }
    properties = {
      reserved = true  # required for Linux
    }
    tags = var.tags
  })
}
```

> **VNet Integration requires at minimum a Premium v2/v3 or Standard SKU.**
> Basic (B1/B2/B3) does not support VNet Integration.

---

## Web App

```hcl
resource "azapi_resource" "web_app" {
  type      = "Microsoft.Web/sites@2022-09-01"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    kind = "app,linux"
    properties = {
      serverFarmId        = azapi_resource.asp.id
      httpsOnly           = true
      publicNetworkAccess = "Disabled"    # disables public inbound
      siteConfig = {
        linuxFxVersion          = "DOTNETCORE|8.0"   # or NODE|20-lts, PYTHON|3.11, etc.
        minTlsVersion           = "1.2"
        ftpsState               = "Disabled"
        http20Enabled           = true
        alwaysOn                = true
        vnetRouteAllEnabled     = true   # route ALL outbound through VNet (not just RFC1918)
      }
      vnetImagePullEnabled      = true   # pull container images through VNet if using ACR
    }
    identity = {
      type = "SystemAssigned"
    }
    tags = var.tags
  })

  response_export_values = ["identity.principalId", "properties.defaultHostName"]
}
```

## VNet Integration (Outbound)

VNet integration is configured as a child resource of `sites`:

```hcl
resource "azapi_resource" "vnet_integration" {
  type      = "Microsoft.Web/sites/networkConfig@2022-09-01"
  name      = "virtualNetwork"
  parent_id = azapi_resource.web_app.id

  body = jsonencode({
    properties = {
      subnetResourceId  = var.integration_subnet_id  # dedicated integration subnet
      swiftSupported    = true
    }
  })
}
```

### Integration Subnet Requirements

- Minimum size: `/26` (64 addresses; `/28` is technically enough but leaves no room)
- Must be **delegated** to `Microsoft.Web/serverFarms`
- Must **not** be the same subnet used for Private Endpoints
- `vnetRouteAllEnabled = true` on the site ensures all outbound goes through VNet

---

## Function App

Function Apps use the same `Microsoft.Web/sites` type with `kind = "functionapp,linux"`:

```hcl
resource "azapi_resource" "func_app" {
  type      = "Microsoft.Web/sites@2022-09-01"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    kind = "functionapp,linux"
    properties = {
      serverFarmId        = azapi_resource.asp.id
      httpsOnly           = true
      publicNetworkAccess = "Disabled"
      siteConfig = {
        linuxFxVersion      = "DOTNET-ISOLATED|8.0"
        minTlsVersion       = "1.2"
        ftpsState           = "Disabled"
        vnetRouteAllEnabled = true
        appSettings = [
          { name = "AzureWebJobsStorage__accountName"; value = var.storage_account_name },
          { name = "AzureWebJobsStorage__credential";  value = "managedidentity" },  # no connection strings
          { name = "FUNCTIONS_EXTENSION_VERSION";       value = "~4" },
          { name = "FUNCTIONS_WORKER_RUNTIME";          value = "dotnet-isolated" },
          { name = "APPLICATIONINSIGHTS_CONNECTION_STRING"; value = var.app_insights_connection_string }
        ]
      }
    }
    identity = { type = "SystemAssigned" }
    tags = var.tags
  })
}
```

> **Storage for Function Apps:** Use `AzureWebJobsStorage__accountName` +
> `AzureWebJobsStorage__credential = "managedidentity"` instead of a connection string.
> This requires the Function App's managed identity to have `Storage Blob Data Owner`,
> `Storage Queue Data Contributor`, and `Storage Table Data Contributor` on the storage account.

## Important Properties

| Property | Required Value | Reason |
|---|---|---|
| `publicNetworkAccess` | `"Disabled"` | No public inbound |
| `httpsOnly` | `true` | TLS required |
| `ftpsState` | `"Disabled"` | No FTP |
| `vnetRouteAllEnabled` | `true` | All outbound via VNet |
| `minTlsVersion` | `"1.2"` | Security baseline |
| Identity | `SystemAssigned` minimum | For Key Vault, Storage, etc. |
