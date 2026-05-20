# PostgreSQL Flexible Server

**ARM Namespace:** `Microsoft.DBforPostgreSQL/flexibleServers`
**Minimum API Version:** `2023-06-01-preview` (stable version lacks key properties)
**Private Access:** VNet injection (not Private Endpoint) — the server is deployed directly into a subnet

> PostgreSQL Flexible Server uses **VNet injection** for private access, not Private Endpoints.
> The server is assigned a private IP within a delegated subnet. There is no public endpoint when
> `network.publicNetworkAccess = "Disabled"`.

---

## Private PostgreSQL Flexible Server

```hcl
resource "azapi_resource" "postgresql" {
  type      = "Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    sku = {
      name = "Standard_D2ds_v4"   # burstable: Standard_B2ms; general: Standard_D*; memory: Standard_E*
      tier = "GeneralPurpose"     # Burstable, GeneralPurpose, or MemoryOptimized
    }
    properties = {
      version              = "16"   # use latest stable: 14, 15, or 16
      administratorLogin   = var.admin_login
      administratorLoginPassword = var.admin_password  # use random_password + Key Vault
      storage = {
        storageSizeGB = 32
        autoGrow      = "Enabled"
      }
      backup = {
        backupRetentionDays  = 7
        geoRedundantBackup   = "Disabled"   # enable for production
      }
      highAvailability = {
        mode = "Disabled"   # or "ZoneRedundant" for production
      }
      network = {
        delegatedSubnetResourceId = var.postgresql_subnet_id
        privateDnsZoneArmResourceId = azapi_resource.postgresql_dns.id
        publicNetworkAccess       = "Disabled"
      }
    }
    tags = var.tags
  })
}
```

### Required Private DNS Zone

```hcl
resource "azapi_resource" "postgresql_dns" {
  type      = "Microsoft.Network/privateDnsZones@2020-06-01"
  name      = "${var.name}.private.postgres.database.azure.com"
  location  = "global"
  parent_id = var.resource_group_id
  body      = jsonencode({})
}

resource "azapi_resource" "postgresql_dns_link" {
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01"
  name      = "postgresql-vnet-link"
  location  = "global"
  parent_id = azapi_resource.postgresql_dns.id

  body = jsonencode({
    properties = {
      virtualNetwork      = { id = var.vnet_id }
      registrationEnabled = false
    }
  })
}
```

### Subnet Requirements

- Minimum size: `/28` (16 addresses; `/27` recommended)
- Must be delegated to `Microsoft.DBforPostgreSQL/flexibleServers`
- Must **not** have a Network Security Group with rules blocking PostgreSQL port (5432)
- The DNS zone must be linked **before** the server is created (note the dependency)

```hcl
# Delegation
resource "azapi_update_resource" "pg_subnet" {
  type        = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  resource_id = var.postgresql_subnet_id

  body = jsonencode({
    properties = {
      delegations = [{
        name = "pg-delegation"
        properties = { serviceName = "Microsoft.DBforPostgreSQL/flexibleServers" }
      }]
    }
  })
}
```

## Important Properties

| Property | Required Value | Reason |
|---|---|---|
| `network.publicNetworkAccess` | `"Disabled"` | VNet-only access |
| `network.delegatedSubnetResourceId` | Set | Required for VNet injection |
| `network.privateDnsZoneArmResourceId` | Set | DNS resolution within VNet |
| `backup.geoRedundantBackup` | `"Enabled"` for prod | RPO protection |
| `highAvailability.mode` | `"ZoneRedundant"` for prod | HA |

## Firewall Rules

When `publicNetworkAccess = "Disabled"`, firewall rules are ignored — no rules needed.
Do not add `0.0.0.0/0` allow-all rules.

## Admin Password

Never hardcode passwords. Use Terraform's `random_password` resource and store in Key Vault:

```hcl
resource "random_password" "pg_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*-_=+?"
}

# Store in Key Vault via azapi_resource (Microsoft.KeyVault/vaults/secrets@2023-02-01)
```
