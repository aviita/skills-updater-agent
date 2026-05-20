# AGENTS.md — Skills Updater Agent

## Why this project exists

### The problem

AI coding assistants like GitHub Copilot CLI gain their power from **skills** — structured instruction files that guide the model's behaviour for a specific domain. A well-written skill encodes hard-won engineering decisions: which Terraform provider to use, which networking topology is mandatory, which API versions are approved, which authentication patterns are required.

These skills rot.

Azure evolves continuously. New API versions supersede old ones. Architectural Decision Records (ADRs) redefine which patterns are approved. Provider releases expand what is possible. Security advisories invalidate assumptions. When a skill falls behind, the model's suggestions silently drift from the team's real standards — and the engineers reviewing that output may not catch subtle regressions like a missing private endpoint, a wrong API version pin, or a disabled RBAC flag that has been re-enabled.

Manual maintenance compounds the problem. Keeping a skill current requires reading release notes, comparing against existing guidance, proposing precise edits, verifying the edits don't conflict with other ADRs, and writing regression tests. A single intake can touch a dozen reference files. Across a team, this work is inconsistent, slow, and easy to deprioritise.

### The solution

This repository contains an **automated, multi-agent pipeline** that keeps the `terraform-azapi` skill perpetually synchronised with upstream changes. The pipeline:

1. **Ingests** any new source — a Confluence ADR, an Azure release-notes page, a doc update, or an advisory — and snapshots it with a stable, version-pinned reference.
2. **Updates** the skill files surgically, proposing only the minimum changes that faithfully reflect the new information while preserving every non-negotiable default (AzAPI-only, zero public network access, private endpoints mandatory for all PaaS, explicit API version pins on every resource).
3. **Reviews** the proposed diff independently, checking for scope creep, conflicting ADRs, invalid API versions, and changelog hygiene — with a structured retry loop before escalating to a human.
4. **Tests** the updated skill by proposing and running targeted evals: simple deterministic assertion tests for specific rule coverage, and trajectory rubric-scored scenario tests for complex multi-resource patterns.

The output is a single branch with four atomic commits — one per stage — ready for human PR review. The human reviews a well-scoped diff with a changelog entry and passing eval results, rather than a sprawling manual edit.

### The `terraform-azapi` skill

The skill being maintained enforces a set of **non-negotiable infrastructure defaults** for Azure Terraform:

| Default | Rule |
|---|---|
| AzAPI-only | No `azurerm_*` resources (data sources allowed). All resources via `azapi_resource`. |
| Zero public network access | `publicNetworkAccess = "Disabled"` everywhere by default. |
| Private Endpoints | Required for all PaaS services (App Services, Key Vault, Storage, Cosmos DB, Event Grid, etc.). |
| VNet injection | Container Apps and PostgreSQL Flexible use VNet injection instead of Private Endpoints. |
| Auth hardening | `disableLocalAuth = true`, `enableRbacAuthorization = true`, `allowSharedKeyAccess = false` on applicable services. |
| Explicit API versions | Every `azapi_resource` must carry an explicit, pinned API version. |

These defaults represent deliberate architectural decisions. The skill updater's primary responsibility is to propagate upstream changes without ever quietly eroding them.

### Who this is for

Platform and infrastructure teams who **publish and maintain AI coding skills** for internal use. If your team relies on Copilot CLI or similar tools to generate Terraform, and you have architectural standards that must be enforced consistently, this pipeline is designed to take the maintenance burden off individual engineers and ensure your skill stays authoritative.

---

## Repository structure

```
skills-updater-agent/
├── skill-updater-agent/       # The pipeline: orchestrator + sub-agent definitions + prompts
│   ├── agents/                # Sub-agent instruction files
│   ├── prompts/               # Reusable extraction and formatting prompts
│   └── scripts/               # Snapshot helpers (Confluence, web URLs)
└── terraform-azapi-skill/     # The skill being maintained
    ├── SKILL.md               # Top-level skill instruction file
    ├── references/            # Per-resource reference files + ADR log + changelog
    └── evals/                 # Eval suites (simple + trajectory) and runner
```

---

## Agents

| Agent | Model | Role |
|---|---|---|
| **orchestrator** | Opus 4 | Entry point. Runs preflight checks, creates the update branch, and coordinates the four stages in sequence. Handles reviewer retry logic and surfaces blockers to the human. |
| **ingester** | Sonnet | Stage 1. Fetches and snapshots the incoming source (Confluence ADR or web URL). Extracts structured metadata without modifying the skill. |
| **updater** | Opus 4 | Stage 2. Proposes surgical, minimal edits to skill files based on the ingester's output. Preserves all non-negotiable defaults. |
| **reviewer** | Opus 4 | Stage 3. Independently reviews the diff for faithfulness, preserved defaults, ADR conflicts, API version validity, and changelog hygiene. Returns `APPROVED` or `CHANGES_REQUESTED` with structured issues. |
| **tester** | Opus 4 | Stage 4. Proposes new evals for changed surfaces, audits existing evals for staleness, and runs the affected subset. Reports regressions but does not block on trajectory regressions alone. |

## Prompts

| Prompt | Purpose |
|---|---|
| `adr-extraction.md` | Teaches the ingester how to map Confluence ADR sections to structured snapshot frontmatter and extract mechanical rules from prose decisions. |
| `changelog-entry.md` | Defines the exact format for `references/changelog.md` entries, including field requirements, link pinning rules, and worked examples. |
| `eval-format.md` | Specifies the JSON schemas for both eval categories (simple assertion-based and trajectory rubric-scored), including required fields, valid assertion types, and rubric weight constraints. |

---

## Conventional commits

This repository uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

### Format

```
type(scope): short imperative description

[optional body — wrap at 72 chars]

[optional footers]
```

- **Subject line:** imperative mood, lowercase, no trailing period, max 72 characters.
- **Body:** use when the *why* or *what* needs more context. Blank line separates it from the subject.
- **Breaking changes:** append `!` after the type/scope, e.g. `feat(skill)!: ...`, and add a `BREAKING CHANGE:` footer.

### Types

| Type | When to use |
|---|---|
| `feat` | A new capability — new agent, new eval, new ingestion source support |
| `fix` | Corrects a bug or incorrect behaviour in an agent, prompt, or script |
| `docs` | Documentation only — AGENTS.md, README, inline comments |
| `chore` | Housekeeping — dependency updates, .gitignore, repo scaffolding |
| `refactor` | Code/prompt restructuring with no behaviour change |
| `test` | Adding or updating evals only |
| `style` | Formatting, whitespace, no logic change |
| `ci` | CI/CD pipeline changes |
| `perf` | Performance improvements to scripts or harnesses |

### Scopes

Scopes are optional but encouraged to signal which part of the repo changed.

| Scope | Area |
|---|---|
| `skill` | Changes to `terraform-azapi-skill/SKILL.md` or top-level skill behaviour |
| `refs` | Changes to `terraform-azapi-skill/references/*.md` |
| `evals` | Changes to `terraform-azapi-skill/evals/` |
| `agents` | Changes to `skill-updater-agent/agents/` |
| `prompts` | Changes to `skill-updater-agent/prompts/` |
| `scripts` | Changes to `skill-updater-agent/scripts/` |
| `docs` | Repository-level documentation |
| `ci` | CI/CD configuration |

### Examples

```
chore: initial commit of skill-updater-agent workspace

docs(agents): add AGENTS.md with project purpose and commit conventions

feat(agents): add dedup check to ingester for already-snapshotted sources

fix(refs): correct PostgreSQL API version floor in references/postgresql.md

test(evals): add trajectory eval for multi-resource private networking scenario

feat(skill)!: require explicit tags block on all azapi_resource definitions

BREAKING CHANGE: The skill now requires a tags block on every azapi_resource.
Existing code without tags will be flagged during review.

refactor(prompts): extract shared assertion types into eval-format.md

chore(scripts): add --dry-run flag to snapshot-url.sh
```

### PR titles

PR titles follow the same `type(scope): subject` format. They become the squash-merge commit message, so they must be valid conventional commits.
