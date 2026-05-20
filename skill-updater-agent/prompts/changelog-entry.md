# Changelog Entry Format

The `references/changelog.md` file in the skill repo is a reverse-chronological log of every
update made to the skill. The updater sub-agent maintains this file.

## Strict format

Every entry follows this exact structure. Newest entries go at the **top** of the file
(immediately after the file's header comment block).

```markdown
## YYYY-MM-DD HH:MM UTC — One-line summary
**Type:** ADR | release-notes | docs | advisory | announcement | other
**Source:** [page title](source-url-with-version-pin-if-confluence)
**Snapshot:** [`adr-archive/...md`](adr-archive/...md)
**Affected:** comma-separated resource types or "skill-wide"
**ADR:** ADR-XXXX or —

2-4 sentence summary of what changed in the skill and why.

**Rule changes:**
- Bullet per concrete rule that was added/changed/removed
- Use past tense: "Added", "Changed", "Removed", "Clarified", "Deprecated"
- Be specific: "Changed minimum API version for Microsoft.KeyVault/vaults from 2023-02-01 to 2023-07-01"
  not "Updated Key Vault API version"
```

## Field rules

- **Timestamp** — UTC, minute precision. Use the time the change is committed, not the time
  the source was published.
- **Type** — pick one. If the source is a Confluence ADR page, always `ADR`.
- **Source** — for Confluence, the URL must include `?pageVersion=N` so the link pins to the
  exact version that was read. For web sources, use the URL as-is plus a snapshot link.
- **Snapshot** — relative path from the skill repo root. Always use a markdown link with
  backticks around the path inside the link text.
- **Affected** — list of ARM resource types in `Microsoft.Namespace/type` form, comma-separated.
  Use `skill-wide` only if the change touches SKILL.md's core principles.
- **ADR** — the ADR id if applicable (e.g., `ADR-0042`); use an em-dash (`—`) otherwise.

## Examples

### ADR ingestion

```markdown
## 2026-05-10 14:23 UTC — Mandate VNet injection for all PostgreSQL deployments
**Type:** ADR
**Source:** [ADR-0042: Private PostgreSQL Only](https://confluence.example.com/x/abc?pageVersion=3)
**Snapshot:** [`adr-archive/ADR-0042-private-postgres-only-v3.md`](adr-archive/ADR-0042-private-postgres-only-v3.md)
**Affected:** Microsoft.DBforPostgreSQL/flexibleServers
**ADR:** ADR-0042

ADR-0042 mandates VNet injection (not Private Endpoint) for all PostgreSQL Flexible Server
deployments. The skill already followed this pattern, but this update makes it an explicit
rule rather than a default. Also formalizes the requirement that the private DNS zone be
created before the server.

**Rule changes:**
- Added explicit prohibition on using Private Endpoint with PostgreSQL Flexible Server
- Added explicit ordering requirement: private DNS zone before server creation
- Linked ADR-0042 from references/postgresql.md
```

### Release notes ingestion

```markdown
## 2026-04-22 09:15 UTC — AzAPI provider 2.0 released
**Type:** release-notes
**Source:** [Azure/azapi v2.0.0 release](https://github.com/Azure/terraform-provider-azapi/releases/tag/v2.0.0)
**Snapshot:** [`source-archive/2026-04-22-azapi-v2-release.md`](source-archive/2026-04-22-azapi-v2-release.md)
**Affected:** skill-wide
**ADR:** —

AzAPI provider 2.0 introduces the new `azapi_resource` schema with improved drift detection
and renames `ignore_body_changes` to `ignore_changes`. Bumped minimum provider version in
SKILL.md. No behavioral changes to existing rules.

**Rule changes:**
- Changed minimum azapi provider version from >= 1.13.0 to >= 2.0.0
- Renamed `ignore_body_changes` to `ignore_changes` in skill examples
```

### Advisory ingestion

```markdown
## 2026-03-08 11:00 UTC — Storage account TLS 1.0/1.1 deprecation enforced
**Type:** advisory
**Source:** [Azure Storage TLS deprecation](https://learn.microsoft.com/...)
**Snapshot:** [`source-archive/2026-03-08-storage-tls-deprecation.md`](source-archive/2026-03-08-storage-tls-deprecation.md)
**Affected:** Microsoft.Storage/storageAccounts
**ADR:** —

Microsoft is enforcing TLS 1.2 minimum for storage accounts starting 2026-04-01. The skill
already required TLS 1.2; this entry records the deprecation and removes a stale note that
mentioned TLS 1.0 as an option for legacy clients.

**Rule changes:**
- Removed deprecated note about TLS 1.0 compatibility
- Reinforced minimumTlsVersion = "TLS1_2" requirement (no behavioral change)
```
