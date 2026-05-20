---
name: terraform-azapi
description: >
  Use this skill whenever writing, reviewing, or modifying Terraform code that targets Azure infrastructure.
  This skill is mandatory when the user mentions Terraform + Azure in any combination, asks to provision
  Azure resources, wants to review or fix Azure Terraform code, or references any of the following:
  azapi_resource, AzAPI provider, Azure Container Apps, App Services, Function Apps, App Insights,
  Key Vault, Storage Accounts, PostgreSQL, Cosmos DB, Event Grid, Event Hubs.
  Always use this skill — do not write Azure Terraform from memory.
---

# Terraform AzAPI Skill

Terraform for Azure using **only** the [AzAPI provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs)
(`Azure/azapi`). The AzureRM provider is **forbidden** — never suggest or use it.

All infrastructure defaults to **zero public network access**. Public access must be explicitly justified
and is never the default.

---

## Provider Setup

```hcl
terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.13.0"
    }
    azurerm = { # ONLY for azurerm_client_config data source
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
  }
}

provider "azapi" {}

# Only acceptable azurerm usage: reading caller identity
provider "azurerm" {
  features {}
  skip_provider_registration = true
}

data "azurerm_client_config" "current" {}
```

> The `azurerm` provider block is permitted **only** to access `azurerm_client_config`.
> All resource provisioning uses `azapi`.

---

## Core Principles

1. **No public network access by default.** Every resource that has a `publicNetworkAccess` or
   `publicNetworkAccessEnabled` field must set it to `Disabled` unless there is a documented,
   approved exception.
2. **Private Endpoints for all PaaS.** Any PaaS resource that supports Private Endpoints must have one.
3. **Private DNS Zones required.** Every Private Endpoint must have a corresponding
   `privatelink.*` DNS zone linked to the VNet.
4. **AzAPI only.** Use `azapi_resource` for all resource creation. Use `azapi_update_resource`
   only when patching a resource you do not own (e.g., updating a subnet delegation on an existing VNet).
5. **Pin API versions.** Every `azapi_resource` must specify an explicit `type` with API version.
   See [Finding API Versions](#finding-api-versions).
6. **Outputs over data sources.** Prefer passing resource IDs via `output`/`var` over querying
   with data sources where possible.

---

## Finding API Versions

Use the AZ CLI to discover valid API versions for any resource type:

```bash
# List all API versions for a resource type
az rest --method GET \
  --url "https://management.azure.com/subscriptions/{sub}/providers/Microsoft.KeyVault?api-version=2021-04-01" \
  --query "resourceTypes[?resourceType=='vaults'].apiVersions[]"

# Generic pattern
az provider show --namespace Microsoft.<Namespace> \
  --query "resourceTypes[?resourceType=='<type>'].apiVersions[]" \
  --output table
```

Always use the **latest stable** (non-preview) API version unless a minimum is specified in
[references/api-versions.md](references/api-versions.md).

---

## azapi_resource Pattern

```hcl
resource "azapi_resource" "example" {
  type      = "Microsoft.Namespace/resourceType@YYYY-MM-DD"
  name      = var.name
  location  = var.location
  parent_id = azapi_resource.resource_group.id  # or var.resource_group_id

  body = jsonencode({
    properties = {
      # resource-specific properties
    }
    tags = var.tags
  })

  response_export_values = ["properties.id", "properties.endpoint"]  # export what you need
}
```

**Rules:**
- `type` format is always `"Namespace/type@YYYY-MM-DD"` — never omit the API version
- `parent_id` is the resource group ID for top-level resources
- `body` uses `jsonencode({})` — never raw JSON strings
- Use `response_export_values` to expose output values; access via `resource.output.properties.<field>`
- Use `ignore_body_changes` for properties Azure mutates after creation (e.g., `["properties.someAutoField"]`)

---

## Private Networking Pattern

Every PaaS resource follows this three-part pattern:

### 1. Disable Public Access (on the resource itself)

```hcl
body = jsonencode({
  properties = {
    publicNetworkAccess = "Disabled"   # or publicNetworkAccessEnabled = false — check ARM schema
    # resource-specific config...
  }
})
```

### 2. Private Endpoint

```hcl
resource "azapi_resource" "pe" {
  type      = "Microsoft.Network/privateEndpoints@2023-04-01"
  name      = "${var.name}-pe"
  location  = var.location
  parent_id = var.resource_group_id

  body = jsonencode({
    properties = {
      subnet = {
        id = var.subnet_id  # dedicated PE subnet, no NSG outbound restriction to Azure backbone
      }
      privateLinkServiceConnections = [{
        name = "${var.name}-plsc"
        properties = {
          privateLinkServiceId = azapi_resource.target.id
          groupIds             = ["<subresource>"]  # see references/private-endpoints.md for groupIds
        }
      }]
    }
  })
}
```

### 3. Private DNS Zone + A Record

```hcl
resource "azapi_resource" "dns_zone" {
  type      = "Microsoft.Network/privateDnsZones@2020-06-01"
  name      = "privatelink.<service>.azure.com"  # see references/private-endpoints.md
  location  = "global"
  parent_id = var.resource_group_id
  body      = jsonencode({})
}

resource "azapi_resource" "dns_vnet_link" {
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01"
  name      = "${var.name}-vnet-link"
  location  = "global"
  parent_id = azapi_resource.dns_zone.id

  body = jsonencode({
    properties = {
      virtualNetwork         = { id = var.vnet_id }
      registrationEnabled    = false
    }
  })
}

resource "azapi_resource" "dns_group" {
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01"
  name      = "default"
  parent_id = azapi_resource.pe.id

  body = jsonencode({
    properties = {
      privateDnsZoneConfigs = [{
        name = "config"
        properties = {
          privateDnsZoneId = azapi_resource.dns_zone.id
        }
      }]
    }
  })
}
```

---

## Resource Reference Index

For resource-specific ARM schemas, groupIds, DNS zone names, and minimum API versions, read:

- [references/container-apps.md](references/container-apps.md) — Container Apps + Container Apps Environment
- [references/app-services.md](references/app-services.md) — App Service Plan, Web Apps, Function Apps, VNet integration
- [references/app-insights.md](references/app-insights.md) — Application Insights, Log Analytics Workspace
- [references/key-vault.md](references/key-vault.md) — Key Vault (secrets, keys, certificates)
- [references/storage.md](references/storage.md) — Storage Accounts, Blob, File, Queue, Table
- [references/postgresql.md](references/postgresql.md) — PostgreSQL Flexible Server
- [references/cosmos-db.md](references/cosmos-db.md) — Cosmos DB accounts, databases, containers
- [references/event-grid-hubs.md](references/event-grid-hubs.md) — Event Grid Topics/Subscriptions, Event Hubs Namespace + Hub
- [references/api-versions.md](references/api-versions.md) — Minimum required API versions per resource type
- [references/private-endpoints.md](references/private-endpoints.md) — groupIds and DNS zone names for all supported resources

**When implementing any of these services, read the relevant reference file before writing code.**

---

## Active ADRs

ADRs that affect this skill are tracked in [references/adrs.md](references/adrs.md).
Always check this file — an ADR may override defaults or mandate specific patterns.

---

## Common Mistakes to Avoid

| Mistake | Correct approach |
|---|---|
| Using `azurerm_*` resources | Use `azapi_resource` |
| Omitting API version from `type` | Always `Namespace/type@YYYY-MM-DD` |
| Setting `publicNetworkAccess = "Enabled"` | Default is `"Disabled"` |
| Skipping Private Endpoint | Required for all supported PaaS |
| Skipping Private DNS Zone | Required alongside every PE |
| Raw JSON string in `body` | Use `jsonencode({})` |
| Using `azapi_update_resource` for owned resources | Only for resources you don't own |
| Hardcoding subscription/tenant IDs | Use `data.azurerm_client_config.current` |
