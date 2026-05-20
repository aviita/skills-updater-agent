# Eval Format Reference

The skill has two eval categories:

- **Simple evals** — `evals/simple/evals.json` — one-shot, string/regex assertions, pass/fail
- **Trajectory evals** — `evals/trajectory/evals.json` — larger scenarios, rubric-based, LLM-judged pairwise against baselines

This file specifies both formats and how the tester sub-agent decides between them.

## When to use which

| The change introduces… | Use a… |
|---|---|
| A specific property requirement | Simple |
| A specific forbidden pattern | Simple |
| An API version floor | Simple |
| A DNS zone, groupId, or RBAC role name | Simple |
| A new multi-resource scenario | Trajectory |
| A pattern where multiple resources must coordinate | Trajectory |
| A rule that's hard to assert with strings | Trajectory |

A single rule change often warrants **both** — a simple eval that mechanically checks the property, and an updated trajectory eval that exercises the rule in context.

## Simple eval schema

```json
{
  "id": "eval-<category>-NNN",
  "category": "<service-short>",
  "prompt": "Realistic developer ask",
  "assertions": [
    {
      "type": "must_contain | must_not_contain | must_match_regex | must_not_match_regex | count_at_least | count_at_most",
      "value": "<string or regex>",
      "count": 2,
      "description": "Human-readable description used in failure output"
    }
  ],
  "covers": ["Microsoft.Namespace/resourceType"],
  "introduced_by": "<changelog slug or 'initial'>",
  "last_updated": "YYYY-MM-DD"
}
```

## Trajectory eval schema

```json
{
  "id": "traj-<scenario-slug>-NNN",
  "category": "<service or cross-cutting>",
  "prompt": "Realistic, larger-scope developer ask producing a complete spec",
  "rubric": [
    {
      "dimension": "<short_name>",
      "weight": 0.20,
      "criteria": "Specific testable language describing what 'good' means for this dimension"
    }
  ],
  "passing_score": 4.0,
  "covers": ["Microsoft.Namespace/resourceType"],
  "introduced_by": "<changelog slug or 'initial'>",
  "last_updated": "YYYY-MM-DD"
}
```

Rubric design:
- 4–6 dimensions per eval
- Weights sum to 1.0
- Always include `azapi_only` when the eval involves Terraform code
- Always include `private_networking_complete` when the eval involves PaaS
- Criteria must be testable from the model's output text — avoid vague words like "good", "clean", "appropriate"

## Categories

| Category | Reference file in skill |
|---|---|
| `key-vault` | `references/key-vault.md` |
| `storage` | `references/storage.md` |
| `postgresql` | `references/postgresql.md` |
| `cosmos-db` | `references/cosmos-db.md` |
| `container-apps` | `references/container-apps.md` |
| `app-services` | `references/app-services.md` |
| `app-insights` | `references/app-insights.md` |
| `event-grid` | `references/event-grid-hubs.md` |
| `event-hubs` | `references/event-grid-hubs.md` |
| `cross-cutting` | Rules from SKILL.md spanning resources |

## Simple assertion types

| Type | Behavior | When to use |
|---|---|---|
| `must_contain` | Substring must appear | Required keyword, property, value |
| `must_not_contain` | Substring must NOT appear | Forbidden patterns (azurerm, public, etc.) |
| `must_match_regex` | POSIX regex must match | Property = value patterns where whitespace varies |
| `must_not_match_regex` | POSIX regex must NOT match | Forbidden assignments |
| `count_at_least` | Substring count ≥ `count` | "At least 2 azapi_resource blocks" |
| `count_at_most` | Substring count ≤ `count` | "At most 1 azurerm provider block" |

## Running evals (the tester invokes these)

```bash
# Simple
./evals/run.sh simple <eval-id>
./evals/run.sh simple --all

# Trajectory (3 runs each by default)
./evals/run.sh trajectory <eval-id>
./evals/run.sh trajectory --all --runs 5
```

Both runners select the harness via `EVAL_HARNESS` (default `copilot-cli`) and the generator model via `GENERATOR_MODEL` (default `claude-sonnet-4-6`). Trajectory mode also uses `JUDGE_MODEL` (default `gpt-5-4`) for pairwise comparison.

## Trajectory baselines and the judge

The trajectory judge compares the new output against a human-blessed baseline at `evals/trajectory/baselines/<eval-id>__<generator-model>.md`. If no baseline exists, the judge scores standalone against the rubric (`pass`/`fail`). Baselines are **never** modified by the agent — only by humans through deliberate PRs.

Verdicts:
- `new_better` / `equivalent` — pipeline continues
- `old_better` / `both_failed` / `fail` — pipeline surfaces to human for review

Per-run scores, verdicts, and metadata (generator model, judge model, harness, skill commit SHA) are appended to `evals/trajectory/trends/<eval-id>.jsonl`. Output content is referenced by SHA-256 hash; the actual text lives in git history (retrievable by checking out the run's `skill_commit_sha`).

## Naming conventions

- Simple IDs: `eval-<category>-NNN`, zero-padded 3-digit number, unique within category
- Trajectory IDs: `traj-<scenario-slug>-NNN`
- `introduced_by`: either `"initial"` (seed set) or the changelog entry slug (e.g., `"2026-05-10-ADR-0042"`)

## Quality bar

A good eval:
- Has a prompt that sounds like a real developer ask
- (Simple) 5–10 focused assertions, mix of positive and negative
- (Trajectory) 4–6 rubric dimensions with concrete, testable criteria
- Covers exactly one scenario or rule
- Has descriptive language that makes failures self-explanatory

A bad eval:
- Reads like a test ("Generate Terraform code containing azapi_resource")
- (Simple) 1–2 assertions (insufficient) or 20+ assertions (brittle)
- (Trajectory) vague rubric criteria that two reasonable humans would score differently
- Combines multiple unrelated services into one prompt
