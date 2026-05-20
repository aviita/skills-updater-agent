#!/usr/bin/env bash
# evals/run.sh — Unified runner for simple and trajectory evals.
#
# Usage:
#   ./evals/run.sh simple <eval-id>            Run one simple eval
#   ./evals/run.sh simple --category <name>    Run all simple evals in category
#   ./evals/run.sh simple --all                Run the full simple suite
#   ./evals/run.sh trajectory <eval-id> [--runs N]
#                                               Run one trajectory eval (default 3 runs)
#   ./evals/run.sh trajectory --all [--runs N]  Run the full trajectory suite
#
# Env:
#   EVAL_HARNESS       Which harness adapter to use. Default: copilot-cli
#   GENERATOR_MODEL    Model for running eval prompts. Default: claude-sonnet-4-6
#   JUDGE_MODEL        Model for the trajectory judge. Default: gpt-5-4
#   JUDGE_MODE         strict | advisory. Default: strict
#                       (advisory tags verdicts when judge model isn't the configured one)
#
# Requires: jq, the configured harness adapter

set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVALS_DIR="$SKILL_ROOT/evals"

EVAL_HARNESS="${EVAL_HARNESS:-copilot-cli}"
GENERATOR_MODEL="${GENERATOR_MODEL:-claude-sonnet-4-6}"
JUDGE_MODEL="${JUDGE_MODEL:-gpt-5-4}"
JUDGE_MODE="${JUDGE_MODE:-strict}"

HARNESS_SCRIPT="$EVALS_DIR/harnesses/${EVAL_HARNESS}.sh"
if [[ ! -x "$HARNESS_SCRIPT" ]]; then
  echo "ERROR: harness adapter not found or not executable: $HARNESS_SCRIPT" >&2
  exit 2
fi

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found in PATH" >&2; exit 2; }
}
require jq

run_harness() {
  # Args: $1=system-prompt-file, $2=user-prompt-string, $3=model
  HARNESS_SYSTEM_PROMPT="$1" \
  HARNESS_USER_PROMPT="$2" \
  HARNESS_MODEL="$3" \
  HARNESS_SKILL_PATH="$SKILL_ROOT" \
    "$HARNESS_SCRIPT"
}

# ─────────────────────────────────────────────────────────────────────
# SIMPLE EVAL MODE
# ─────────────────────────────────────────────────────────────────────

run_simple() {
  local evals_file="$EVALS_DIR/simple/evals.json"
  local runner_prompt="$EVALS_DIR/simple/runner-prompt.md"
  local filter

  case "${1:-}" in
    --all) filter='.' ;;
    --category) [[ -n "${2:-}" ]] || { echo "Usage: run.sh simple --category <name>"; exit 2; }
                filter=".[] | select(.category == \"$2\")" ;;
    "")    echo "Usage: run.sh simple {<eval-id> | --category <name> | --all}"; exit 2 ;;
    *)     filter=".[] | select(.id == \"$1\")" ;;
  esac

  local pass=0 fail=0 err=0

  while IFS= read -r eval_obj; do
    local id prompt
    id=$(echo "$eval_obj" | jq -r '.id')
    prompt=$(echo "$eval_obj" | jq -r '.prompt')

    echo "── $id ─────────────────────────────────"
    echo "Prompt: $prompt"

    local harness_result
    if ! harness_result=$(run_harness "$runner_prompt" "$prompt" "$GENERATOR_MODEL"); then
      echo "  ERROR running harness ($EVAL_HARNESS):"
      echo "$harness_result" | jq -r '.error' | sed 's/^/    /'
      err=$((err+1))
      continue
    fi

    local ok output
    ok=$(echo "$harness_result" | jq -r '.ok')
    output=$(echo "$harness_result" | jq -r '.output')
    if [[ "$ok" != "true" ]]; then
      echo "  ERROR: harness reported failure"
      echo "$harness_result" | jq -r '.error' | sed 's/^/    /'
      err=$((err+1))
      continue
    fi

    # Evaluate assertions
    local eval_pass=true
    while IFS= read -r assertion; do
      local a_type a_value a_desc a_count
      a_type=$(echo "$assertion"  | jq -r '.type')
      a_value=$(echo "$assertion" | jq -r '.value')
      a_desc=$(echo "$assertion"  | jq -r '.description')
      a_count=$(echo "$assertion" | jq -r '.count // empty')

      case "$a_type" in
        must_contain)
          if echo "$output" | grep -qF -- "$a_value"; then echo "  ✓ $a_desc"
          else echo "  ✗ $a_desc  (expected: $a_value)"; eval_pass=false; fi
          ;;
        must_not_contain)
          if echo "$output" | grep -qF -- "$a_value"; then echo "  ✗ $a_desc  (forbidden: $a_value)"; eval_pass=false
          else echo "  ✓ $a_desc"; fi
          ;;
        must_match_regex)
          if echo "$output" | grep -Eq -- "$a_value"; then echo "  ✓ $a_desc"
          else echo "  ✗ $a_desc  (regex: $a_value)"; eval_pass=false; fi
          ;;
        must_not_match_regex)
          if echo "$output" | grep -Eq -- "$a_value"; then echo "  ✗ $a_desc  (forbidden regex: $a_value)"; eval_pass=false
          else echo "  ✓ $a_desc"; fi
          ;;
        count_at_least)
          local actual; actual=$(echo "$output" | grep -oF -- "$a_value" | wc -l | tr -d ' ')
          if [[ "$actual" -ge "$a_count" ]]; then echo "  ✓ $a_desc  ($actual ≥ $a_count)"
          else echo "  ✗ $a_desc  ($actual < $a_count)"; eval_pass=false; fi
          ;;
        count_at_most)
          local actual; actual=$(echo "$output" | grep -oF -- "$a_value" | wc -l | tr -d ' ')
          if [[ "$actual" -le "$a_count" ]]; then echo "  ✓ $a_desc  ($actual ≤ $a_count)"
          else echo "  ✗ $a_desc  ($actual > $a_count)"; eval_pass=false; fi
          ;;
        *) echo "  ⚠ Unknown assertion type: $a_type"; eval_pass=false ;;
      esac
    done < <(echo "$eval_obj" | jq -c '.assertions[]')

    if $eval_pass; then pass=$((pass+1)); echo "  → PASS"
    else fail=$((fail+1)); echo "  → FAIL"; fi
    echo
  done < <(jq -c "$filter" "$evals_file")

  echo "═══════════════════════════════════════"
  echo "Simple evals: $pass passed, $fail failed, $err errored"
  echo "Generator:    $GENERATOR_MODEL via $EVAL_HARNESS"
  echo "═══════════════════════════════════════"
  [[ "$fail" -eq 0 && "$err" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────────
# TRAJECTORY EVAL MODE
# ─────────────────────────────────────────────────────────────────────

run_trajectory() {
  local evals_file="$EVALS_DIR/trajectory/evals.json"
  local runner_prompt="$EVALS_DIR/trajectory/runner-prompt.md"
  local judge_prompt="$EVALS_DIR/trajectory/judge-prompt.md"
  local trends_dir="$EVALS_DIR/trajectory/trends"
  local baselines_dir="$EVALS_DIR/trajectory/baselines"

  local filter=""
  local runs=3
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)   target="all"; shift ;;
      --runs)  runs="$2"; shift 2 ;;
      *)       target="$1"; shift ;;
    esac
  done

  if [[ -z "$target" ]]; then
    echo "Usage: run.sh trajectory {<eval-id> | --all} [--runs N]"; exit 2
  fi
  if [[ "$target" == "all" ]]; then filter='.'
  else filter=".[] | select(.id == \"$target\")"; fi

  local skill_sha="unknown"
  if (cd "$SKILL_ROOT" && git rev-parse HEAD >/dev/null 2>&1); then
    skill_sha=$(cd "$SKILL_ROOT" && git rev-parse HEAD)
  fi

  local total_failed=0

  while IFS= read -r eval_obj; do
    local id prompt rubric passing_score
    id=$(echo "$eval_obj" | jq -r '.id')
    prompt=$(echo "$eval_obj" | jq -r '.prompt')
    rubric=$(echo "$eval_obj" | jq -c '.rubric')
    passing_score=$(echo "$eval_obj" | jq -r '.passing_score')

    echo "── $id ($runs runs) ─────────────────────"

    # Baseline filename includes generator model — explicit pairing
    local generator_slug
    generator_slug=$(echo "$GENERATOR_MODEL" | tr './' '__')
    local baseline_file="$baselines_dir/${id}__${generator_slug}.md"
    local has_baseline=false
    local baseline_output=""
    if [[ -f "$baseline_file" ]]; then
      has_baseline=true
      baseline_output=$(cat "$baseline_file")
    fi

    # Collect N runs
    local run_outputs=()
    local total_elapsed=0
    local i=1
    while [[ $i -le $runs ]]; do
      echo "  Run $i/$runs..."
      local harness_result
      if ! harness_result=$(run_harness "$runner_prompt" "$prompt" "$GENERATOR_MODEL"); then
        echo "    ERROR running harness"
        total_failed=$((total_failed+1))
        i=$((i+1))
        continue
      fi
      local ok output elapsed
      ok=$(echo "$harness_result" | jq -r '.ok')
      output=$(echo "$harness_result" | jq -r '.output')
      elapsed=$(echo "$harness_result" | jq -r '.elapsed_ms')
      if [[ "$ok" != "true" ]]; then
        echo "    Harness failed: $(echo "$harness_result" | jq -r '.error' | head -c 200)"
        i=$((i+1))
        continue
      fi
      run_outputs+=("$output")
      total_elapsed=$((total_elapsed + elapsed))
      i=$((i+1))
    done

    if [[ ${#run_outputs[@]} -eq 0 ]]; then
      echo "  No successful runs; skipping judge."
      total_failed=$((total_failed+1))
      continue
    fi

    # For each run, invoke the judge (pairwise if baseline, else standalone)
    local judge_results=()
    local k=1
    for new_output in "${run_outputs[@]}"; do
      local judge_input
      if $has_baseline; then
        judge_input=$(jq -nc \
          --arg scenario "$prompt" \
          --argjson rubric "$rubric" \
          --argjson passing_score "$passing_score" \
          --arg baseline "$baseline_output" \
          --arg new "$new_output" \
          --arg gen_model "$GENERATOR_MODEL" \
          --arg gen_harness "$EVAL_HARNESS" \
          '{
            mode: "pairwise",
            scenario: $scenario,
            rubric: $rubric,
            passing_score: $passing_score,
            baseline: {output: $baseline},
            new: {output: $new, generator_model: $gen_model, generator_harness: $gen_harness}
          }')
      else
        judge_input=$(jq -nc \
          --arg scenario "$prompt" \
          --argjson rubric "$rubric" \
          --argjson passing_score "$passing_score" \
          --arg new "$new_output" \
          --arg gen_model "$GENERATOR_MODEL" \
          --arg gen_harness "$EVAL_HARNESS" \
          '{
            mode: "standalone",
            scenario: $scenario,
            rubric: $rubric,
            passing_score: $passing_score,
            new: {output: $new, generator_model: $gen_model, generator_harness: $gen_harness}
          }')
      fi

      echo "  Judging run $k/$runs (judge=$JUDGE_MODEL, mode=$([[ $has_baseline == true ]] && echo pairwise || echo standalone))..."
      local judge_result
      if ! judge_result=$(run_harness "$judge_prompt" "$judge_input" "$JUDGE_MODEL"); then
        echo "    Judge harness failed."
        k=$((k+1))
        continue
      fi
      local j_ok j_output
      j_ok=$(echo "$judge_result" | jq -r '.ok')
      j_output=$(echo "$judge_result" | jq -r '.output')
      if [[ "$j_ok" != "true" ]]; then
        echo "    Judge reported failure: $(echo "$judge_result" | jq -r '.error' | head -c 200)"
        k=$((k+1))
        continue
      fi

      # Parse judge's JSON output (strip code fences if present)
      local cleaned
      cleaned=$(echo "$j_output" | sed -e 's/```json//g' -e 's/```//g')
      if ! echo "$cleaned" | jq empty >/dev/null 2>&1; then
        echo "    Judge produced non-JSON output; skipping."
        k=$((k+1))
        continue
      fi
      judge_results+=("$cleaned")
      local verdict; verdict=$(echo "$cleaned" | jq -r '.verdict')
      echo "    Verdict: $verdict"
      k=$((k+1))
    done

    # Compose a trend entry (one line per run)
    local trend_file="$trends_dir/${id}.jsonl"
    mkdir -p "$(dirname "$trend_file")"
    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local run_id; run_id="$timestamp-$RANDOM"

    local advisory=false
    if [[ "$JUDGE_MODE" == "advisory" || "$JUDGE_MODEL" != "gpt-5-4" ]]; then
      advisory=true
    fi

    local idx=0
    for judge_result in "${judge_results[@]}"; do
      local new_output="${run_outputs[$idx]}"
      # SHA256 of output content
      local content_hash; content_hash=$(echo -n "$new_output" | sha256sum | awk '{print "sha256:"$1}')

      local trend_entry
      trend_entry=$(jq -nc \
        --arg run_id "$run_id-$idx" \
        --arg timestamp "$timestamp" \
        --arg skill_sha "$skill_sha" \
        --arg gen_model "$GENERATOR_MODEL" \
        --arg gen_harness "$EVAL_HARNESS" \
        --arg judge_model "$JUDGE_MODEL" \
        --arg judge_harness "$EVAL_HARNESS" \
        --argjson advisory "$advisory" \
        --arg content_hash "$content_hash" \
        --argjson judge "$judge_result" \
        '{
          run_id: $run_id,
          timestamp: $timestamp,
          skill_commit_sha: $skill_sha,
          generator: {model: $gen_model, harness: $gen_harness},
          judge: {model: $judge_model, harness: $judge_harness, advisory: $advisory},
          output: {content_hash: $content_hash},
          judgment: $judge
        }')
      echo "$trend_entry" >> "$trend_file"
      idx=$((idx+1))
    done

    # Summarize this eval
    local n_runs=${#judge_results[@]}
    local verdicts; verdicts=$(printf '%s\n' "${judge_results[@]}" | jq -r '.verdict' | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ')
    echo "  Eval $id: $n_runs runs judged. Verdicts: $verdicts"

    # Determine if this eval stage requires human intervention
    local needs_human=false
    for judge_result in "${judge_results[@]}"; do
      local v; v=$(echo "$judge_result" | jq -r '.verdict')
      if [[ "$v" == "old_better" || "$v" == "both_failed" || "$v" == "fail" ]]; then
        needs_human=true
      fi
    done
    if $needs_human; then
      echo "  ⚠ HUMAN REVIEW NEEDED: at least one run regressed or failed. See $trend_file"
      total_failed=$((total_failed+1))
    fi
    echo
  done < <(jq -c "$filter" "$evals_file")

  echo "═══════════════════════════════════════"
  echo "Trajectory evals complete."
  echo "Generator:        $GENERATOR_MODEL via $EVAL_HARNESS"
  echo "Judge:            $JUDGE_MODEL via $EVAL_HARNESS  (mode: $JUDGE_MODE)"
  echo "Evals needing review: $total_failed"
  echo "═══════════════════════════════════════"
  [[ "$total_failed" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────────
# DISPATCH
# ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  simple)     shift; run_simple "$@" ;;
  trajectory) shift; run_trajectory "$@" ;;
  help|--help|-h|"")
    cat <<EOF
Usage:
  $0 simple <eval-id>            Run one simple eval
  $0 simple --category <name>    Run all simple evals in category
  $0 simple --all                Run the full simple suite
  $0 trajectory <eval-id> [--runs N]   Run one trajectory eval (default --runs 3)
  $0 trajectory --all [--runs N]       Run the full trajectory suite

Env:
  EVAL_HARNESS=copilot-cli      Harness adapter to use
  GENERATOR_MODEL=claude-sonnet-4-6
  JUDGE_MODEL=gpt-5-4
  JUDGE_MODE=strict             strict | advisory
EOF
    ;;
  *)
    echo "Unknown command: $1"; exit 2 ;;
esac
