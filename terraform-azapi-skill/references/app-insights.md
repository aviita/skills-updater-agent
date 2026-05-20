# Application Insights & Log Analytics

**ARM Namespaces:**
- `Microsoft.OperationalInsights/workspaces` — Log Analytics Workspace
- `Microsoft.Insights/components` — Application Insights

**Minimum API Versions:** `2022-10-01` (Log Analytics), `2020-02-02` (App Insights)

> App Insights should always be **workspace-based** (linked to Log Analytics).
> Classic (non-workspace) App Insights is deprecated.
> Neither resource supports Private Endpoints directly — network isolation is through
> **Private Link Scopes** if required, but standard deployments use public ingestion endpoints
> with data encrypted in transit and at rest.

---

## Log Analytics Workspace

```hcl
resource "azapi_resource" "log_analytics" {
  type      = "Microsoft.OperationalInsights/workspaces@2022-10-01"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    properties = {
      sku                    = { name = "PerGB2018" }
      retentionInDays        = 30
      publicNetworkAccessForIngestion = "Enabled"   # Required unless using Private Link Scope
      publicNetworkAccessForQuery     = "Enabled"
    }
    tags = var.tags
  })

  response_export_values = ["properties.customerId", "properties.workspaceId"]
}
```

> To get the workspace shared key (needed for Container Apps log config), use `azapi_resource_action`:
> ```hcl
> data "azapi_resource_action" "law_keys" {
>   type        = "Microsoft.OperationalInsights/workspaces@2022-10-01"
>   resource_id = azapi_resource.log_analytics.id
>   action      = "sharedKeys"
>   method      = "POST"
>   response_export_values = ["primarySharedKey"]
> }
> ```

---

## Application Insights (Workspace-Based)

```hcl
resource "azapi_resource" "app_insights" {
  type      = "Microsoft.Insights/components@2020-02-02"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    kind = "web"
    properties = {
      Application_Type                = "web"
      WorkspaceResourceId             = azapi_resource.log_analytics.id
      publicNetworkAccessForIngestion = "Enabled"   # see note above
      publicNetworkAccessForQuery     = "Enabled"
      RetentionInDays                 = 30
      DisableIpMasking                = false
    }
    tags = var.tags
  })

  response_export_values = ["properties.ConnectionString", "properties.InstrumentationKey"]
}
```

Use `properties.ConnectionString` (not InstrumentationKey) for all modern SDK configuration.
