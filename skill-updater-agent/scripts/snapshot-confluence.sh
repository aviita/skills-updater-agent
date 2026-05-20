#!/usr/bin/env bash
# snapshot-confluence.sh
# Helper invoked by the ingester sub-agent to save a versioned snapshot of a Confluence page.
# This script does NOT call Confluence directly — the agent does that via Atlassian MCP.
# This script just writes the file with the correct header and naming.
#
# Usage:
#   snapshot-confluence.sh \
#     --skill-repo /path/to/terraform-azapi-skill \
#     --adr-id ADR-0042 \
#     --slug private-postgres-only \
#     --version 3 \
#     --source-url "https://confluence.example.com/x/abc?pageVersion=3" \
#     --page-updated "2026-04-15T10:30:00Z" \
#     --status Active \
#     --valid-until 2027-01-01 \
#     --title "Private PostgreSQL Only" \
#     --content-file /tmp/adr-body.md
#
# Outputs the snapshot path on stdout.

set -euo pipefail

SKILL_REPO=""
ADR_ID=""
SLUG=""
VERSION=""
SOURCE_URL=""
PAGE_UPDATED=""
STATUS=""
VALID_UNTIL=""
TITLE=""
CONTENT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-repo)    SKILL_REPO="$2"; shift 2 ;;
    --adr-id)        ADR_ID="$2"; shift 2 ;;
    --slug)          SLUG="$2"; shift 2 ;;
    --version)       VERSION="$2"; shift 2 ;;
    --source-url)    SOURCE_URL="$2"; shift 2 ;;
    --page-updated)  PAGE_UPDATED="$2"; shift 2 ;;
    --status)        STATUS="$2"; shift 2 ;;
    --valid-until)   VALID_UNTIL="$2"; shift 2 ;;
    --title)         TITLE="$2"; shift 2 ;;
    --content-file)  CONTENT_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in SKILL_REPO ADR_ID SLUG VERSION SOURCE_URL PAGE_UPDATED STATUS TITLE CONTENT_FILE; do
  if [[ -z "${!v}" ]]; then
    echo "ERROR: missing --${v,,}" >&2
    exit 2
  fi
done

VALID_UNTIL="${VALID_UNTIL:-Indefinite}"
ARCHIVE_DIR="$SKILL_REPO/adr-archive"
mkdir -p "$ARCHIVE_DIR"

OUTPUT="$ARCHIVE_DIR/${ADR_ID}-${SLUG}-v${VERSION}.md"

if [[ -e "$OUTPUT" ]]; then
  echo "ERROR: snapshot already exists: $OUTPUT" >&2
  exit 3
fi

FETCHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$OUTPUT" <<EOF
---
adr_id: $ADR_ID
title: $TITLE
source_url: $SOURCE_URL
fetched_at: $FETCHED_AT
page_version: $VERSION
page_updated_at: $PAGE_UPDATED
status: $STATUS
valid_until: $VALID_UNTIL
---

# Original ADR Content

EOF

cat "$CONTENT_FILE" >> "$OUTPUT"

echo "$OUTPUT"
