# Skill Evals

Two eval categories with very different shapes:

## Simple evals (`simple/`)

One-shot, deterministic. A prompt is sent to the model; the model's response is checked against string/regex assertions. Pass/fail.

These exist to catch concrete rule violations (wrong provider, missing property, public access enabled). They are fast, cheap, and run on every change.

## Trajectory evals (`trajectory/`)

Larger scenarios with rubric-based scoring. An LLM judge (default: GPT 5.4) compares each new output **pairwise against a human-blessed baseline** for that eval, scoring both sides on a weighted rubric and producing a verdict:

- `new_better` — new output beats baseline
- `equivalent` — within noise
- `old_better` — **regression** (human review needed)
- `both_failed` — neither output reached `passing_score` (human review needed)

If no baseline exists for an eval/generator pair, the judge scores standalone against the rubric (`pass` or `fail`).

Each trajectory eval runs **3 times by default** (parameterizable). Per-run scores and verdicts are recorded in `trajectory/trends/<eval-id>.jsonl` for stability and drift analysis. The actual model outputs live in the git commit history (the trend entry stores the SHA-256 content hash and the commit SHA where the output was committed by the runner — see "Output snapshots" below).

## File layout

```
evals/
├── README.md                          This file
├── run.sh                             Unified runner (simple + trajectory modes)
├── harnesses/
│   └── copilot-cli.sh                 GitHub Copilot CLI adapter (default)
├── simple/
│   ├── evals.json                     Assertion-based evals
│   └── runner-prompt.md               System prompt for simple runs
└── trajectory/
    ├── evals.json                     Rubric-based evals
    ├── runner-prompt.md               System prompt for trajectory runs
    ├── judge-prompt.md                System prompt for the judge model
    ├── baselines/
    │   └── <eval-id>__<generator>.md  Human-blessed baseline per (eval, generator) pair
    └── trends/
        └── <eval-id>.jsonl            One line per run — scores, verdicts, metadata
```

## Running

```bash
# Simple
./evals/run.sh simple --all
./evals/run.sh simple --category postgresql
./evals/run.sh simple eval-keyvault-001

# Trajectory
./evals/run.sh trajectory --all                       # default 3 runs each
./evals/run.sh trajectory traj-orders-platform-001    # one eval, 3 runs
./evals/run.sh trajectory --all --runs 5              # 5 runs each (more stability data)
./evals/run.sh trajectory traj-orders-platform-001 --runs 1   # quick single-shot
```

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `EVAL_HARNESS` | `copilot-cli` | Which adapter under `harnesses/` to use |
| `GENERATOR_MODEL` | `claude-sonnet-4-6` | Model that produces eval outputs |
| `JUDGE_MODEL` | `gpt-5-4` | Model that judges trajectory outputs |
| `JUDGE_MODE` | `strict` | `strict` or `advisory`. In advisory mode, verdicts from non-default judge models are marked advisory rather than failing the run |

## Harness abstraction

The runner calls `harnesses/<name>.sh` rather than `copilot` directly. Each adapter reads env vars, invokes its underlying tool, and returns a JSON record on stdout. This lets you swap GH Copilot CLI for direct API calls in CI without touching the runner.

Contract:
- **Inputs (env):** `HARNESS_MODEL`, `HARNESS_SYSTEM_PROMPT` (file path), `HARNESS_USER_PROMPT` (string), `HARNESS_SKILL_PATH`
- **Outputs (stdout):** `{output, model, harness, harness_version, elapsed_ms, ok, error}`

Currently shipped: `copilot-cli`. Add adapters by dropping new scripts into `harnesses/` and selecting via `EVAL_HARNESS`.

## Model identity in records

Every trend entry records the generator model + harness, the judge model + harness, and (when the judge isn't the configured one) flags the verdict as `advisory`. This is what makes the evals model-aware: you can run the same eval through Sonnet 4.6 and Opus 4 and compare trend lines side-by-side without one polluting the other. Per-generator baselines (`baselines/<eval-id>__<generator>.md`) keep comparisons honest.

## Baselines

Baselines are **never moved automatically.** When a `new_better` verdict comes back, a human reviews and decides whether to promote the new output to baseline. To promote, copy the model's output from the relevant commit into `baselines/<eval-id>__<generator>.md` in a deliberate PR.

When no baseline exists yet, the first standalone-mode run that achieves `pass` is a good candidate for blessing — but again, this is a human decision.

## Trends file format

Each line in `trends/<eval-id>.jsonl` is one judge run for one eval invocation:

```json
{
  "run_id": "2026-05-10T14:23:00Z-31415-0",
  "timestamp": "2026-05-10T14:23:00Z",
  "skill_commit_sha": "abc123def456",
  "generator": {"model": "claude-sonnet-4-6", "harness": "copilot-cli"},
  "judge": {"model": "gpt-5-4", "harness": "copilot-cli", "advisory": false},
  "output": {"content_hash": "sha256:..."},
  "judgment": {
    "mode": "pairwise",
    "scores": { ... },
    "verdict": "equivalent",
    "reasoning": "...",
    "regressions": [],
    "improvements": [],
    "observations": []
  }
}
```

Append-only. Diffable in PRs. Useful for spotting:
- **Fluctuation** — verdicts oscillating between runs on the same skill state
- **Slow degradation** — scores trending down over multiple skill changes
- **Cliffs** — sudden drop tied to a specific commit

## Output snapshots — retrieving the actual text

The trend record stores only the content hash, not the output itself. To see what the model actually produced for a given run:

1. Find the trend entry of interest (look up `run_id` or `timestamp`)
2. Note its `skill_commit_sha`
3. `git checkout <skill_commit_sha>` (or `git show <skill_commit_sha>` to peek)
4. Re-run the eval at that commit to reproduce, OR look at any output the runner attached to that commit's PR notes

This is intentional: full outputs are heavy and noisy; trend files are light and grep-able. If you find yourself reaching for the full output frequently, that's a signal a baseline update may be due.

## When the eval stage requires human review

The runner exits non-zero if any trajectory eval run produced `old_better`, `both_failed`, or `fail`. The skill-updater agent's tester sub-agent will surface these to the human and not auto-commit anything that depends on a passing eval verdict.

The human options are:
1. **Rerun** — the result may be noise; rerun with `--runs 5` for more signal
2. **Accept the regression** — promote the new baseline if the new behavior is actually preferred
3. **Reject the change** — the skill update introduced a real regression; revert or amend
