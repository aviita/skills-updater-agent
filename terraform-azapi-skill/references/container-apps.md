# Azure Container Apps

**ARM Namespaces:**
- `Microsoft.App/managedEnvironments` — Container Apps Environment
- `Microsoft.App/containerApps` — Container App

**Minimum API Version:** `2023-05-01`

> Container Apps do **not** use Private Endpoints. Network isolation is achieved via
> **VNet injection** with an internal-only environment (`vnetConfiguration.internal = true`).
> This means the environment gets no public inbound IP — all traffic must come through the VNet.

---

## Container Apps Environment (Internal)

```hcl
resource "azapi_resource" "cae" {
  type      = "Microsoft.App/managedEnvironments@2023-05-01"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    properties = {
      vnetConfiguration = {
        internal               = true   # no public IP — mandatory
        infrastructureSubnetId = var.cae_subnet_id  # /23 minimum recommended
      }
      appLogsConfiguration = {
        destination = "log-analytics"
        logAnalyticsConfiguration = {
          customerId = azapi_resource.log_analytics.output.properties.customerId
          sharedKey  = jsondecode(azapi_resource.log_analytics.output.properties).sharedKey  # use azapi_resource_action to get keys
        }
      }
    }
    tags = var.tags
  })

  response_export_values = [
    "properties.staticIp",
    "properties.defaultDomain"
  ]
}
```

### Subnet Requirements for Container Apps Environment

- Minimum size: `/23` (512 addresses)
- The subnet must be **delegated** to `Microsoft.App/environments`
- Must not be shared with other workloads

```hcl
# Delegation — use azapi_update_resource if subnet is pre-existing
resource "azapi_update_resource" "cae_subnet_delegation" {
  type        = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  resource_id = var.cae_subnet_id

  body = jsonencode({
    properties = {
      delegations = [{
        name = "cae-delegation"
        properties = {
          serviceName = "Microsoft.App/environments"
        }
      }]
    }
  })
}
```

### DNS for Internal Environment

When `internal = true`, the environment gets a private static IP and a `defaultDomain` like
`<env-name>.<region>.azurecontainerapps.io`. You must create a private DNS zone to resolve this:

```hcl
resource "azapi_resource" "cae_dns" {
  type      = "Microsoft.Network/privateDnsZones@2020-06-01"
  name      = azapi_resource.cae.output.properties.defaultDomain
  location  = "global"
  parent_id = var.resource_group_id
  body      = jsonencode({})
}

resource "azapi_resource" "cae_dns_wildcard" {
  type      = "Microsoft.Network/privateDnsZones/A@2020-06-01"
  name      = "*"
  parent_id = azapi_resource.cae_dns.id

  body = jsonencode({
    properties = {
      ttl = 300
      aRecords = [{
        ipv4Address = azapi_resource.cae.output.properties.staticIp
      }]
    }
  })
}

resource "azapi_resource" "cae_dns_vnet_link" {
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01"
  name      = "cae-vnet-link"
  location  = "global"
  parent_id = azapi_resource.cae_dns.id

  body = jsonencode({
    properties = {
      virtualNetwork      = { id = var.vnet_id }
      registrationEnabled = false
    }
  })
}
```

---

## Container App

```hcl
resource "azapi_resource" "container_app" {
  type      = "Microsoft.App/containerApps@2023-05-01"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    properties = {
      managedEnvironmentId = azapi_resource.cae.id
      configuration = {
        ingress = {
          external   = false     # internal traffic only — no public ingress
          targetPort = 8080
          transport  = "http"
          allowInsecure = false
        }
        secrets = [
          # Reference Key Vault secrets via managed identity — do not inline secret values
          # Use secretRef pattern below
        ]
      }
      template = {
        containers = [{
          name  = var.container_name
          image = var.container_image
          resources = {
            cpu    = 0.5
            memory = "1Gi"
          }
          env = [
            {
              name  = "SOME_SECRET"
              secretRef = "some-secret-name"  # references configuration.secrets
            }
          ]
        }]
        scale = {
          minReplicas = 1
          maxReplicas = 10
        }
      }
    }
    identity = {
      type = "SystemAssigned"  # or UserAssigned with userAssignedIdentities
    }
    tags = var.tags
  })

  response_export_values = ["identity.principalId", "properties.configuration.ingress.fqdn"]
}
```

## Important Properties

| Property | Required Value | Reason |
|---|---|---|
| `vnetConfiguration.internal` | `true` | No public IP on environment |
| `ingress.external` | `false` | No public ingress on app |
| `identity.type` | `SystemAssigned` (min) | Required for Key Vault / Storage access |
| Secret values | Via Key Vault reference | Never inline secrets in body |

## Managed Identity → Key Vault

Assign `Key Vault Secrets User` to the Container App's managed identity:

```hcl
resource "azapi_resource" "ca_kv_role" {
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.key_vault.id}/SecretsUser/${azapi_resource.container_app.id}")
  parent_id = azapi_resource.key_vault.id

  body = jsonencode({
    properties = {
      roleDefinitionId = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
      principalId      = azapi_resource.container_app.output.identity.principalId
      principalType    = "ServicePrincipal"
    }
  })
}
```
