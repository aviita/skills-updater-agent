# Private Endpoints Reference

Quick lookup for `groupIds` and `privateDnsZone` names required when creating Private Endpoints.

## groupIds and DNS Zones by Service

| Service | groupId | Private DNS Zone |
|---|---|---|
| Key Vault | `vault` | `privatelink.vaultcore.azure.net` |
| Storage — Blob | `blob` | `privatelink.blob.core.windows.net` |
| Storage — File | `file` | `privatelink.file.core.windows.net` |
| Storage — Queue | `queue` | `privatelink.queue.core.windows.net` |
| Storage — Table | `table` | `privatelink.table.core.windows.net` |
| PostgreSQL Flexible | `postgresqlServer` | `privatelink.postgres.database.azure.com` |
| Cosmos DB (SQL) | `Sql` | `privatelink.documents.azure.com` |
| Cosmos DB (MongoDB) | `MongoDB` | `privatelink.mongo.cosmos.azure.com` |
| Cosmos DB (Table) | `Table` | `privatelink.table.cosmos.azure.com` |
| Event Hubs Namespace | `namespace` | `privatelink.servicebus.windows.net` |
| Event Grid Topic | `topic` | `privatelink.eventgrid.azure.net` |
| Event Grid Domain | `domain` | `privatelink.eventgrid.azure.net` |
| App Service / Function App | `sites` | `privatelink.azurewebsites.net` |
| Container Registry | `registry` | `privatelink.azurecr.io` |

> **Note:** Container Apps Environments do not use Private Endpoints directly.
> They use VNet injection (internal-only environment). See `container-apps.md`.

## Subnet Requirements

The subnet used for Private Endpoints:
- Must have `privateEndpointNetworkPolicies` set to `Disabled` (default for PE subnets)
- Should be dedicated (not shared with app workloads)
- Does **not** require a Network Security Group, but one may be attached — ensure it does not block
  traffic to Azure backbone (168.63.129.16)

```hcl
# Disabling PE network policies on a subnet (azapi_update_resource if subnet is pre-existing)
resource "azapi_update_resource" "pe_subnet_policies" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  resource_id = var.pe_subnet_id

  body = jsonencode({
    properties = {
      privateEndpointNetworkPolicies = "Disabled"
    }
  })
}
```

## DNS Resolution Notes

- Private DNS zones must be linked to the VNet where resolution happens (not just where the PE lives)
- If using a hub-spoke model, link DNS zones to the **hub** VNet (where DNS resolver lives)
- Use `registrationEnabled = false` on VNet links — auto-registration is not used for PE zones
- If using Azure Private DNS Resolver, ensure forwarding rules point to the correct `privatelink.*` zones
