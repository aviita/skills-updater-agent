# Event Grid & Event Hubs

---

## Event Hubs

**ARM Namespace:** `Microsoft.EventHub/namespaces`
**Minimum API Version:** `2022-10-01-preview`
**Private Endpoint groupId:** `namespace`
**Private DNS Zone:** `privatelink.servicebus.windows.net`

### Private Event Hubs Namespace

```hcl
resource "azapi_resource" "eventhub_ns" {
  type      = "Microsoft.EventHub/namespaces@2022-10-01-preview"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    sku = {
      name     = "Standard"   # Basic lacks consumer groups; Premium for dedicated capacity
      tier     = "Standard"
      capacity = 1
    }
    properties = {
      publicNetworkAccess      = "Disabled"
      disableLocalAuth         = true      # force Entra ID; disable SAS keys
      minimumTlsVersion        = "1.2"
      zoneRedundant            = false     # set true for production
      networkRuleSets = {
        # Inline network rule set (alternative to separate resource)
        properties = {
          defaultAction                  = "Deny"
          publicNetworkAccess            = "Disabled"
          trustedServiceAccessEnabled    = true
          ipRules                        = []
          virtualNetworkRules            = []
        }
      }
    }
    tags = var.tags
  })
}
```

### Event Hub

```hcl
resource "azapi_resource" "eventhub" {
  type      = "Microsoft.EventHub/namespaces/eventhubs@2022-10-01-preview"
  name      = var.hub_name
  parent_id = azapi_resource.eventhub_ns.id

  body = jsonencode({
    properties = {
      messageRetentionInDays = 7
      partitionCount         = 4   # cannot change after creation; plan carefully
      status                 = "Active"
    }
  })
}
```

### Consumer Group

```hcl
resource "azapi_resource" "consumer_group" {
  type      = "Microsoft.EventHub/namespaces/eventhubs/consumergroups@2022-10-01-preview"
  name      = var.consumer_group_name
  parent_id = azapi_resource.eventhub.id
  body      = jsonencode({ properties = {} })
}
```

### Event Hubs RBAC Roles

| Role | Use Case |
|---|---|
| `Azure Event Hubs Data Sender` | Publish events |
| `Azure Event Hubs Data Receiver` | Consume events |
| `Azure Event Hubs Data Owner` | Full access |

> `disableLocalAuth = true` disables all SAS-based connection strings.
> All producers and consumers must use managed identity + RBAC.

---

## Event Grid

**ARM Namespace:** `Microsoft.EventGrid/topics`
**Minimum API Version:** `2022-06-15`
**Private Endpoint groupId:** `topic`
**Private DNS Zone:** `privatelink.eventgrid.azure.net`

### Private Event Grid Topic

```hcl
resource "azapi_resource" "eventgrid_topic" {
  type      = "Microsoft.EventGrid/topics@2022-06-15"
  name      = var.name
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    properties = {
      publicNetworkAccess = "Disabled"
      disableLocalAuth    = true         # force Entra ID; disable SAS keys
      inputSchema         = "EventGridSchema"  # or CloudEventSchemaV1_0
      inboundIpRules      = []
    }
    tags = var.tags
  })
}
```

### Event Grid Subscription (Push to Event Hub)

```hcl
resource "azapi_resource" "eg_subscription" {
  type      = "Microsoft.EventGrid/eventSubscriptions@2022-06-15"
  name      = var.subscription_name
  parent_id = azapi_resource.eventgrid_topic.id

  body = jsonencode({
    properties = {
      destination = {
        endpointType = "EventHub"
        properties = {
          resourceId = azapi_resource.eventhub.id
        }
      }
      eventDeliverySchema = "EventGridSchema"
      retryPolicy = {
        maxDeliveryAttempts      = 30
        eventTimeToLiveInMinutes = 1440
      }
      deadLetterDestination = {
        endpointType = "StorageBlob"
        properties = {
          resourceId  = azapi_resource.storage.id
          blobContainerName = "dead-letter"
        }
      }
    }
  })
}
```

## Important Properties (Both Services)

| Property | Required Value | Reason |
|---|---|---|
| `publicNetworkAccess` | `"Disabled"` | No public ingestion endpoint |
| `disableLocalAuth` | `true` | Force Entra ID; disable SAS/keys |
| `minimumTlsVersion` | `"1.2"` | Security baseline (Event Hubs) |
| Dead letter destination | Set for subscriptions | Avoid silent event loss |
