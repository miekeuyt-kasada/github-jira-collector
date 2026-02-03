#!/bin/bash
# Enrich brag doc items with Jira ticket metadata
# Usage: ./enrich_with_jira.sh <input_bragdoc.json> <output_bragdoc.json>
# Example: ./enrich_with_jira.sh bragdoc-data-2025-12.json bragdoc-data-2025-12-jira.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_DIR="$SCRIPT_DIR/../api"

INPUT_FILE="$1"
OUTPUT_FILE="$2"

if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "Usage: $0 <input_bragdoc.json> <output_bragdoc.json>" >&2
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE" >&2
  exit 1
fi

# Check if Jira env vars are set
if [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_BASE_URL:-}" ]; then
  echo "⚠️  Warning: Jira environment variables not set. Skipping Jira enrichment." >&2
  echo "   To enable: set JIRA_EMAIL, JIRA_API_TOKEN, JIRA_BASE_URL" >&2
  cp "$INPUT_FILE" "$OUTPUT_FILE"
  exit 0
fi

echo "🎫 Enriching brag doc with Jira metadata..."

# Extract unique ticket numbers from brag items
ticket_keys=$(jq -r '
  (if type == "object" and has("bragItems") then .bragItems elif type == "array" then . else [] end)
  | map(.ticketNo // empty)
  | unique
  | .[]
' "$INPUT_FILE")

if [ -z "$ticket_keys" ]; then
  echo "  No ticket numbers found in brag doc. Skipping Jira enrichment." >&2
  cp "$INPUT_FILE" "$OUTPUT_FILE"
  exit 0
fi

# Fetch Jira data for all tickets
echo "  Found $(echo "$ticket_keys" | wc -l | tr -d ' ') unique tickets"
jira_data=$("$API_DIR/get_jira_ticket.sh" $ticket_keys 2>&1 | tail -n1)

# Enrich brag items with Jira metadata
jq -s '
  .[0] as $bragdoc |
  .[1] as $jira_tickets |
  
  # Build lookup map from Jira data
  ($jira_tickets | map({
    key: .ticket_key,
    value: {
      epic_key: .epic_key,
      epic_name: .epic_name,
      parent_key: .parent_key,
      labels: (.labels | fromjson),
      status: .status,
      issue_type: .issue_type,
      priority: .priority,
      assignee: .assignee,
      reporter: .reporter
    }
  }) | from_entries) as $jira_lookup |
  
  # Process brag items
  $bragdoc | 
  if type == "object" and has("bragItems") then
    .bragItems |= map(
      . as $item |
      if .ticketNo and $jira_lookup[.ticketNo] then
        . + {
          jiraMetadata: $jira_lookup[.ticketNo]
        }
      else
        .
      end
    ) |
    .
  elif type == "array" then
    map(
      . as $item |
      if .ticketNo and $jira_lookup[.ticketNo] then
        . + {
          jiraMetadata: $jira_lookup[.ticketNo]
        }
      else
        .
      end
    )
  else
    .
  end
' "$INPUT_FILE" <(echo "$jira_data") > "$OUTPUT_FILE"

echo "✅ Jira-enriched brag doc saved to: $OUTPUT_FILE"
