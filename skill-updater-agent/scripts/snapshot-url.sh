#!/usr/bin/env bash
# snapshot-url.sh
# Helper invoked by the ingester sub-agent to save a dated snapshot of a web URL.
# Like snapshot-confluence.sh, this script does NOT fetch — the agent does that via web tooling.
# This script writes the file with the correct header and naming.
#
# Usage:
#   snapshot-url.sh \
#     --skill-repo /path/to/terraform-azapi-skill \
#     --slug azapi-v2-release \
#     --source-url "https://github.com/Azure/terraform-provider-azapi/releases/tag/v2.0.0" \
#     --page-title "AzAPI v2.0.0 Release Notes" \
#     --type release-notes \
#     --publication-date 2026-04-22 \
#     --content-file /tmp/release-notes.md
#
# Outputs the snapshot path on stdout.

set -euo pipefail

SKILL_REPO=""
SLUG=""
SOURCE_URL=""
PAGE_TITLE=""
TYPE=""
PUB_DATE=""
CONTENT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-repo)        SKILL_REPO="$2"; shift 2 ;;
    --slug)              SLUG="$2"; shift 2 ;;
    --source-url)        SOURCE_URL="$2"; shift 2 ;;
    --page-title)        PAGE_TITLE="$2"; shift 2 ;;
    --type)              TYPE="$2"; shift 2 ;;
    --publication-date)  PUB_DATE="$2"; shift 2 ;;
    --content-file)      CONTENT_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in SKILL_REPO SLUG SOURCE_URL PAGE_TITLE TYPE CONTENT_FILE; do
  if [[ -z "${!v}" ]]; then
    echo "ERROR: missing --${v,,}" >&2
    exit 2
  fi
done

case "$TYPE" in
  release-notes|docs|advisory|announcement|other) ;;
  *) echo "ERROR: --type must be one of: release-notes, docs, advisory, announcement, other" >&2; exit 2 ;;
esac

ARCHIVE_DIR="$SKILL_REPO/source-archive"
mkdir -p "$ARCHIVE_DIR"

DATE_PREFIX=$(date -u +"%Y-%m-%d")
OUTPUT="$ARCHIVE_DIR/${DATE_PREFIX}-${SLUG}.md"

if [[ -e "$OUTPUT" ]]; then
  # Append a counter to disambiguate same-day snapshots
  i=2
  while [[ -e "$ARCHIVE_DIR/${DATE_PREFIX}-${SLUG}-${i}.md" ]]; do
    i=$((i+1))
  done
  OUTPUT="$ARCHIVE_DIR/${DATE_PREFIX}-${SLUG}-${i}.md"
fi

FETCHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$OUTPUT" <<EOF
---
source_url: $SOURCE_URL
fetched_at: $FETCHED_AT
page_title: $PAGE_TITLE
publication_date: ${PUB_DATE:-null}
type: $TYPE
---

# Original Content

EOF

cat "$CONTENT_FILE" >> "$OUTPUT"

echo "$OUTPUT"
