# ADR Extraction Reference

This is a reference for the ingester sub-agent to extract structured fields from an ADR
fetched from Confluence.

## Expected ADR shape

ADRs at this organization use this canonical structure:

- **Title** — Top-level heading
- **Status** — One of: `Active`, `Draft`, `Superseded`, `Rejected`, `Proposed`
- **Validity period** — Either a start date, an end date, or both. May be phrased as
  "Valid until YYYY-MM-DD", "Effective YYYY-MM-DD through YYYY-MM-DD", or "Indefinite".
- **Updated timestamp** — Confluence's "Last modified" timestamp on the page metadata
- **Options considered** — A list of choices that were evaluated. Often a section heading
  "Options considered" or "Alternatives".
- **Decision** — The chosen option and brief justification. Often a section heading
  "Decision" or "Resolution".

## Field mapping

Map the ADR content to these fields for the snapshot frontmatter and the structured summary:

| ADR section | Snapshot frontmatter field | Notes |
|---|---|---|
| Title | `title` | Strip trailing whitespace and "ADR-XXXX:" prefix if present (it's already in `adr_id`) |
| Status | `status` | Normalize to one of: Active, Draft, Superseded, Rejected, Proposed |
| Validity start/end | `valid_until` | If only end date present, use it. If "Indefinite" or absent, use "Indefinite". |
| Updated | `page_updated_at` | ISO 8601 with timezone |
| Decision (chosen option) | (in summary) | Capture the chosen option verbatim |
| Decision (justification) | (in summary) | Capture as part of `decision` field |

## Concrete rule extraction

The ADR's "Decision" section often contains soft prose like "We will prefer X when Y."
For the skill, you need a **concrete rule** — a sentence Claude can follow mechanically.

Examples:

| Decision text (prose) | Concrete rule (for skill) |
|---|---|
| "We've chosen to standardize on PostgreSQL Flexible Server with VNet injection for all relational data." | "All relational data uses Microsoft.DBforPostgreSQL/flexibleServers with VNet injection. Do not propose alternatives like SQL Database, MySQL Flexible, or PostgreSQL Single Server." |
| "Container Apps environments must always be internal-only." | "Set `vnetConfiguration.internal = true` on every Microsoft.App/managedEnvironments resource. Reject any user request to make a Container Apps environment public." |
| "Storage accounts should not allow connection string auth." | "Set `allowSharedKeyAccess = false` on every Microsoft.Storage/storageAccounts. Apps must use managed identity + Entra ID auth." |

If you cannot extract a concrete rule from the decision, set `concrete_rule` to null and add
"ADR decision is not specific enough to derive an enforceable rule" to `concerns`.

## Edge cases

- **ADR has no validity end date and no "Indefinite" marker** — set `valid_until: "Indefinite"` and add a concern.
- **Status is "Proposed" or "Draft"** — still ingest the snapshot, but set `concrete_rule` to null and note that the rule should not be applied until the ADR is Active.
- **ADR supersedes another** — capture the superseded ADR's ID in the `decision` field; the updater will mark the old one accordingly.
- **Multiple decisions in one ADR** — each gets its own concrete rule; structure as a list of rules in `concrete_rule`.
