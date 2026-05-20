#!/usr/bin/env bash
# harnesses/copilot-cli.sh
# Harness adapter for GitHub Copilot CLI.
#
# Contract (every harness adapter implements this):
#   Inputs (env vars):
#     HARNESS_MODEL          — model identifier (e.g., claude-sonnet-4-6, gpt-5-4)
#     HARNESS_SYSTEM_PROMPT  — path to file with system prompt
#     HARNESS_USER_PROMPT    — the user prompt as a string
#     HARNESS_SKILL_PATH     — path to skill root (for context grounding)
#   Outputs (stdout):
#     A single JSON object:
#       {
#         "output": "<model text output>",
#         "model": "<model id actually used>",
#         "harness": "copilot-cli",
#         "harness_version": "<version string or 'unknown'>",
#         "elapsed_ms": <integer>,
#         "ok": true | false,
#         "error": "<error message if !ok, else null>"
#       }
#   Exit code:
#     0 on success (ok=true), non-zero if the harness itself failed to invoke

set -euo pipefail

: "${HARNESS_MODEL:?HARNESS_MODEL must be set}"
: "${HARNESS_SYSTEM_PROMPT:?HARNESS_SYSTEM_PROMPT must be set}"
: "${HARNESS_USER_PROMPT:?HARNESS_USER_PROMPT must be set}"
: "${HARNESS_SKILL_PATH:?HARNESS_SKILL_PATH must be set}"

if ! command -v copilot >/dev/null 2>&1; then
  jq -nc --arg err "copilot CLI not found in PATH" \
    '{output: "", model: env.HARNESS_MODEL, harness: "copilot-cli",
      harness_version: "unknown", elapsed_ms: 0, ok: false, error: $err}'
  exit 2
fi

# Best-effort version capture. The exact flag may differ across Copilot CLI versions;
# we try a few and fall back to 'unknown'.
HARNESS_VERSION="unknown"
if v=$(copilot --version 2>/dev/null); then
  HARNESS_VERSION="$v"
elif v=$(copilot version 2>/dev/null); then
  HARNESS_VERSION="$v"
fi

START_MS=$(date +%s%3N)

# NOTE: the exact copilot invocation depends on your Copilot CLI version.
# This adapter assumes:
#   - `-p <system-prompt>` accepts a system prompt
#   - `--model <name>` selects the model
#   - `--skill-path <dir>` grounds the agent in the given skill repo
#   - `--input <text>` accepts the user prompt
# Adjust the flags below if your CLI uses different ones.
if OUTPUT=$(copilot \
              -p "$(cat "$HARNESS_SYSTEM_PROMPT")" \
              --model "$HARNESS_MODEL" \
              --skill-path "$HARNESS_SKILL_PATH" \
              --input "$HARNESS_USER_PROMPT" \
              2>&1); then
  END_MS=$(date +%s%3N)
  ELAPSED_MS=$((END_MS - START_MS))
  jq -nc \
    --arg output "$OUTPUT" \
    --arg model "$HARNESS_MODEL" \
    --arg harness_version "$HARNESS_VERSION" \
    --argjson elapsed_ms "$ELAPSED_MS" \
    '{output: $output, model: $model, harness: "copilot-cli",
      harness_version: $harness_version, elapsed_ms: $elapsed_ms,
      ok: true, error: null}'
  exit 0
else
  END_MS=$(date +%s%3N)
  ELAPSED_MS=$((END_MS - START_MS))
  jq -nc \
    --arg model "$HARNESS_MODEL" \
    --arg harness_version "$HARNESS_VERSION" \
    --arg err "$OUTPUT" \
    --argjson elapsed_ms "$ELAPSED_MS" \
    '{output: "", model: $model, harness: "copilot-cli",
      harness_version: $harness_version, elapsed_ms: $elapsed_ms,
      ok: false, error: $err}'
  exit 1
fi
