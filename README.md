# Skill Maintenance Experiment

An experiment in making AI skill development more **predictable** and **faster to iterate on**, using evals as the quality assurance backbone.

## What this is

A two-part workspace exploring whether a skill (in this case, a Terraform-on-Azure skill) can be maintained as a living artifact — updated continuously as ADRs, provider releases, and policy changes accumulate — without the usual drift, forgetting, and regression that plagues hand-edited prompt files.

The hypothesis: with an agent loop that ingests changes, edits the skill, reviews its own edits, and validates against evals, skill maintenance can shift from "one careful human edit at a time, hoping nothing broke" to "small, frequent, observable changes with regression detection."

```
This repo/
├── terraform-azapi-skill/      The skill being maintained
└── skill-updater-agent/        The agent that maintains it
```

## The skill

`terraform-azapi-skill/` is an opinionated Claude skill for writing Terraform on Azure using **only the AzAPI provider** (AzureRM is forbidden in the target environment), with **zero public network access** as the default for every resource. It covers Container Apps, App Services, App Insights, Key Vault, Storage, PostgreSQL Flexible Server, Cosmos DB, and Event Grid/Hubs.

The skill is structured as a top-level `SKILL.md` plus per-service reference files under `references/`. Active ADRs are tracked separately and may override defaults. A `changelog.md` records every change made to the skill, linking back to the source material (Confluence ADR version, Azure docs URL, etc.).

## The agent

`skill-updater-agent/` is a GitHub Copilot CLI agent that updates the skill in response to new information. It's a four-stage pipeline:

```
INPUT (Confluence URL or web URL)
    │
    ▼
[ingester]   Sonnet — fetches & snapshots (version-pinned for Confluence, dated for web)
    │
    ▼
[updater]    Opus — proposes precise, minimal skill edits
    │
    ▼
[reviewer]   Opus — independent review; one retry allowed before human intervention
    │
    ▼
[tester]     Opus — proposes evals, runs the affected subset, flags regressions
    │
    ▼
Branch with 4 commits, ready for human PR review
```

The agent never opens a PR, never moves a baseline, never deploys anything. It produces a reviewable diff. The human stays in the loop on every meaningful judgment.

## The evals

Quality assurance is the part of this experiment most worth paying attention to. The skill has **two eval categories** intentionally kept separate:

**Simple evals** — one-shot, deterministic, string/regex assertions. Pass/fail. These catch concrete rule violations (wrong provider, missing property, public access enabled). They are cheap and run on every change.

**Trajectory evals** — larger scenarios (e.g., "design a complete private orders platform") scored by an LLM judge doing **pairwise comparison** against a human-blessed baseline. The judge produces verdicts like `new_better`, `equivalent`, `old_better`, or `both_failed`. These exist because some quality dimensions — module coherence, completeness across multiple resources, faithful interpretation of an ADR — can't be checked with string matching.

Each trajectory eval runs multiple times per invocation (default 3) so stability is visible alongside correctness. Verdicts and scores are recorded in append-only trend files committed to the skill repo. Full output text lives in git history rather than on disk, addressable by content hash + commit SHA.

Crucially, the agent never moves baselines. When the new output beats the baseline, that's a signal — a human decides whether to bless the new output as the new standard. This is the load-bearing part: it's what keeps the system honest as the skill evolves.

## What's predictable about this

A few things that this setup makes more predictable than ad-hoc skill editing:

- **Provenance.** Every skill change links back to the source material (versioned Confluence URL, dated web snapshot). You can always answer "why does the skill say this?"
- **Scope.** The agent's edits are narrow by construction — the reviewer blocks scope creep, and the diff is small enough for humans to actually read.
- **Regression visibility.** Trajectory eval verdicts surface drift that wouldn't show up in static assertions. A subtle change that makes the model worse at a complex scenario gets caught.
- **Model and harness identity.** Every eval result records which model produced it and through which harness. Comparing GPT 5.4 vs Sonnet 4.6 doesn't pollute trend lines. Switching from Copilot CLI to direct API calls doesn't silently change baselines.

## What's faster to iterate on

The same setup makes iteration cheaper:

- A new ADR becomes a 5-minute pipeline run instead of a half-day of careful editing
- A failed eval points at a specific rubric dimension that regressed, not "something's worse"
- The same agent works for one ADR or twenty — batching doesn't change the workflow
- Local runs are immediate; CI catches regressions you missed

## What this is not

- **Not autonomous.** The agent stops at a branch. The human reviews and merges. The human blesses new baselines.
- **Not a deployment validator.** Evals check that the skill produces correct code, not that the code deploys. End-to-end deployment validation is a separate manual exercise outside this loop.
- **Not finished.** This is experimentation. Several design decisions (default run counts, judge model choice, baseline policy, harness adapters for CI) are deliberately conservative starting points expected to change once we have real usage data.

## Open questions worth tracking

Things this experiment is set up to answer, but hasn't yet:

- **Eval stability** — how much variance do we actually see across 3 runs? Is 3 enough? Too many? The trend files will tell us within a few weeks of use.
- **Baseline maintenance cost** — how often do baselines need re-blessing as the skill evolves? If it's "every change," the model is too tight; if it's "never," it's too loose.
- **Reviewer effectiveness** — does the independent review stage actually catch updater mistakes, or does the updater + reviewer collapse into agreement? Worth instrumenting.
- **Judge bias** — does GPT 5.4 systematically favor certain styles even within the rubric? Pairwise comparison reduces this risk but doesn't eliminate it.
- **Skill ceiling** — at what point does a single SKILL.md + references model break down? If we add 30 more resource types, is the skill still maintainable as a flat file structure?

## Where to start reading

Roughly in this order:

1. `terraform-azapi-skill/SKILL.md` — what the skill actually says
2. `terraform-azapi-skill/references/` — per-service detail
3. `terraform-azapi-skill/evals/README.md` — how quality is measured
4. `skill-updater-agent/README.md` — how updates happen
5. `skill-updater-agent/agents/orchestrator.md` — the pipeline in detail

## Status

Experimental. Treat everything here as a hypothesis to be tested rather than a system to be relied on.
