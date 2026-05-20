# Skill Updater Agent

A GitHub Copilot CLI agent that keeps the [`terraform-azapi`](../terraform-azapi-skill) skill in sync with new ADRs, Azure announcements, and provider release notes.

## What it does

```
INPUT (Confluence URL or web URL)
    │
    ▼
[ingester]   Sonnet — fetches & snapshots (versioned for Confluence, dated for web)
    │
    ▼
[updater]    Opus 4 — proposes precise skill edits
    │
    ▼
[reviewer]   Opus 4 — independent review (max 1 retry)
    │
    ▼
[tester]     Opus 4 — proposes evals (simple + trajectory), runs affected subset
    │
    ▼
Branch with 4 commits, ready for human PR review
```

## Prerequisites

- GitHub Copilot CLI (`copilot` command) installed and authenticated
- Atlassian MCP preconfigured for your Confluence space
- `git`, `jq`, and `bash` available
- The `terraform-azapi` skill repo cloned locally
- Models accessible via Copilot CLI: `claude-sonnet-4-6` (generator + ingester), `claude-opus-4` (updater, reviewer, tester), `gpt-5-4` (trajectory judge)

## Installation

The agent is installed globally so you can invoke it from inside the skill repo.

```bash
git clone <agent-repo-url>
cd skill-updater-agent

mkdir -p ~/.config/github-copilot/agents/skill-updater
cp -r agents prompts scripts ~/.config/github-copilot/agents/skill-updater/

ln -sf ~/.config/github-copilot/agents/skill-updater/agents/orchestrator.md \
       ~/.config/github-copilot/agents/skill-updater.md
```

## Usage

From inside the skill repo:

```bash
# Ingest an ADR from Confluence
copilot @skill-updater "Ingest https://confluence.example.com/x/abc"

# Ingest an Azure announcement
copilot @skill-updater "Ingest https://learn.microsoft.com/en-us/azure/..."

# Ingest a local ADR markdown file
copilot @skill-updater "Ingest ./drafts/ADR-0042.md"
```

The agent will:
1. Verify the working tree is clean, you're on `main`, and the eval harness (`copilot`) is callable
2. Create a branch `update/<date>-<slug>`
3. Run all four stages, committing once per stage
4. Print the branch name, commit list, changelog entry, and eval results summary
5. Stop — you review the branch and open the PR yourself

## Repo layout

```
skill-updater-agent/
├── README.md                   This file
├── agents/
│   ├── orchestrator.md         Entry point — coordinates the pipeline
│   ├── ingester.md             Fetches & snapshots (Sonnet)
│   ├── updater.md              Proposes skill edits (Opus 4)
│   ├── reviewer.md             Independent review (Opus 4)
│   └── tester.md               Eval generation + local run (Opus 4)
├── prompts/
│   ├── adr-extraction.md       How to parse ADR fields from Confluence
│   ├── changelog-entry.md      Format spec for changelog.md entries
│   └── eval-format.md          Simple + trajectory eval schemas
└── scripts/
    ├── snapshot-confluence.sh  Writes versioned ADR snapshot files
    └── snapshot-url.sh         Writes dated web-source snapshot files
```

## Iteration & failure modes

| Failure | Behavior |
|---|---|
| Atlassian MCP unavailable | Stop, ask user to verify MCP setup |
| Harness (`copilot`) not callable | Stop, ask user to verify CLI install + auth |
| Reviewer requests changes | Updater gets one second-pass attempt with reviewer's notes, then re-review. If still failing, branch left with first updater commit + first review for manual resolution |
| Trajectory eval: `old_better` / `both_failed` / `fail` | Eval files + trends still committed. Surface to human with verdict per run. Three paths: rerun with `--runs 5`, update baseline (deliberate PR), or revert |
| Harness errors mid-eval | Tester retries once per failing eval; persistent errors recorded but don't block the branch |
| Working tree dirty | Stop before doing anything |

## Eval system overview

The skill has two eval categories with different shapes:

**Simple evals** — one-shot deterministic, assertion-based, pass/fail. Cheap; catch concrete rule violations.

**Trajectory evals** — larger scenarios scored by an LLM judge (GPT 5.4) doing **pairwise comparison** against a human-blessed baseline:
- New output vs baseline → score both, compute verdict
- 3 runs per eval by default for stability assessment
- Verdicts written to `evals/trajectory/trends/<eval-id>.jsonl` (committed)
- Full output text lives in git history (referenced by SHA-256 hash + commit SHA)
- Baselines (`evals/trajectory/baselines/<eval-id>__<model>.md`) are **never** moved by the agent — only by humans

Read `evals/README.md` in the skill repo for the full mechanism.

## Models per stage

| Stage | Model | Why |
|---|---|---|
| Ingester | `claude-sonnet-4-6` | Fast, accurate at structured extraction |
| Updater | `claude-opus-4` | Surgical editing of nuanced skill rules — wants the strongest reasoner |
| Reviewer | `claude-opus-4` | Independent verification benefits from the strongest reasoner |
| Tester | `claude-opus-4` | Eval design is subtle; strongest reasoner pays off |
| Eval generator (run by tester) | `claude-sonnet-4-6` | The model under evaluation. Cheaper than Opus for the volume of eval runs |
| Trajectory judge (run by tester) | `gpt-5-4` | Different model family from generator reduces self-judgment bias |

Override via env vars when running evals directly:

```bash
GENERATOR_MODEL=claude-opus-4 JUDGE_MODEL=gpt-5-4 ./evals/run.sh trajectory --all
```

## Harness abstraction

The skill's eval runner calls `evals/harnesses/<name>.sh` rather than `copilot` directly. The default adapter is `copilot-cli.sh`. CI environments can add their own adapter (e.g., direct API calls) and select via `EVAL_HARNESS=...`. Every trend entry records which harness ran, so harness-introduced drift is detectable.

Currently shipped: `copilot-cli`. CI adapters can be added when needed.

## CI integration (future)

The eval suite is designed to run in CI:

```bash
./evals/run.sh simple --all
./evals/run.sh trajectory --all --runs 5
```

When CI's harness doesn't match the local one (e.g., GPT 5.4 unavailable), `JUDGE_MODE=advisory` tags those verdicts as advisory rather than authoritative. A future GitHub Actions workflow will gate PRs on simple-eval pass and trajectory-eval non-regression.

A further future integration: Azure AI Foundry running the agent pipeline non-interactively against new ADRs as they're published, opening PRs automatically.

## What the agent does NOT do

- Run `terraform plan`. The skill is documentation; evals validate behavior, not deployability. End-to-end deployment validation is a separate manual workflow outside this pipeline.
- Modify trajectory eval baselines. Only humans bless baselines.
- Open the PR. The human reviews the branch and opens the PR.
- Retry beyond configured limits (1 updater retry, 1 tester harness retry per eval).
