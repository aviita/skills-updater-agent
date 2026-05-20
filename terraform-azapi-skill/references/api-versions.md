# Minimum API Versions

These are the **minimum** acceptable API versions per resource type. Always use the latest stable
version at or above the minimum. Use `az provider show` to find newer stable versions.

```bash
az provider show --namespace Microsoft.<Namespace> \
  --query "resourceTypes[?resourceType=='<type>'].apiVersions[]" \
  --output table
```

## Version Floor Table

| Resource Type (azapi `type` string) | Minimum API Version | Notes |
|---|---|---|
| `Microsoft.App/managedEnvironments` | `2023-05-01` | Container Apps Environment |
| `Microsoft.App/containerApps` | `2023-05-01` | Container Apps |
| `Microsoft.Web/serverfarms` | `2022-09-01` | App Service Plan |
| `Microsoft.Web/sites` | `2022-09-01` | Web App / Function App |
| `Microsoft.Web/sites/config` | `2022-09-01` | App settings, VNet integration config |
| `Microsoft.Insights/components` | `2020-02-02` | Application Insights |
| `Microsoft.OperationalInsights/workspaces` | `2022-10-01` | Log Analytics |
| `Microsoft.KeyVault/vaults` | `2023-02-01` | Key Vault |
| `Microsoft.Storage/storageAccounts` | `2023-01-01` | Storage Account |
| `Microsoft.DBforPostgreSQL/flexibleServers` | `2023-06-01-preview` | PostgreSQL Flexible (use preview — stable lags) |
| `Microsoft.DocumentDB/databaseAccounts` | `2023-04-15` | Cosmos DB |
| `Microsoft.EventHub/namespaces` | `2022-10-01-preview` | Event Hubs Namespace |
| `Microsoft.EventHub/namespaces/eventhubs` | `2022-10-01-preview` | Event Hub |
| `Microsoft.EventGrid/topics` | `2022-06-15` | Event Grid Topic |
| `Microsoft.EventGrid/eventSubscriptions` | `2022-06-15` | Event Grid Subscription |
| `Microsoft.Network/privateEndpoints` | `2023-04-01` | Private Endpoint |
| `Microsoft.Network/privateDnsZones` | `2020-06-01` | Private DNS Zone |
| `Microsoft.Network/privateDnsZones/virtualNetworkLinks` | `2020-06-01` | DNS VNet Link |
| `Microsoft.Network/privateEndpoints/privateDnsZoneGroups` | `2023-04-01` | DNS Zone Group |
| `Microsoft.Network/virtualNetworks` | `2023-04-01` | VNet |
| `Microsoft.Network/virtualNetworks/subnets` | `2023-04-01` | Subnet |

## Preview API Versions

Some resources only have meaningful properties in preview API versions (e.g., PostgreSQL Flexible).
Using a preview version is acceptable when:
- No stable version exists with the required properties
- The resource type is noted above as requiring preview
- The preview version is from a major provider (Microsoft.DBforPostgreSQL, Microsoft.App, etc.)

Never use preview versions for networking resources (Microsoft.Network).
