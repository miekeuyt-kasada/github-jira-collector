#!/bin/bash
# Enrich LLM-generated brag doc with database metadata
# Usage: ./enrich_bragdoc.sh <llm_output.json> <db_raw_data.json> <output.json>
# Example: ./enrich_bragdoc.sh july-interpreted.json july-raw.json bragdoc-data-2025-07.json

set -e

LLM_OUTPUT="$1"
DB_RAW_DATA="$2"
OUTPUT_FILE="$3"

if [ -z "$LLM_OUTPUT" ] || [ -z "$DB_RAW_DATA" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "Usage: $0 <llm_output.json> <db_raw_data.json> <output.json>" >&2
  exit 1
fi

if [ ! -f "$LLM_OUTPUT" ]; then
  echo "Error: LLM output file not found: $LLM_OUTPUT" >&2
  exit 1
fi

if [ ! -f "$DB_RAW_DATA" ]; then
  echo "Error: DB raw data file not found: $DB_RAW_DATA" >&2
  exit 1
fi

# Use jq to enrich the LLM output with metadata from DB
jq -s '
  .[0] as $llm |
  .[1] as $db |
  
  # Build lookup maps from DB data
  ($db.prs | map({
    key: (.pr_number | tostring),
    value: {
      prId: .pr_number,
      ticketNo: .jira_ticket,
      dates: {
        start: (.first_commit_date // .created_at),
        end: (.merged_at // .closed_at)
      },
      repo: .repo
    }
  }) | from_entries) as $pr_lookup |
  
  # Process each LLM-generated brag item
  $llm | map(
    . as $item |
    
    # Try to extract PR number from achievement text or other fields
    # Look for patterns like "PR #123" or "#123"
    (
      ((.achievement // "") + " " + (.context // "") + " " + (.outcomes // ""))
      | match("#([0-9]+)"; "g")
      | .captures[0].string
    ) as $pr_match |
    
    # Enrich with metadata if we found a PR match
    if $pr_match and $pr_lookup[$pr_match] then
      . + {
        prId: $pr_lookup[$pr_match].prId,
        ticketNo: $pr_lookup[$pr_match].ticketNo,
        dates: (
          if .dates then .dates 
          else $pr_lookup[$pr_match].dates 
          end
        )
      }
    else
      # No PR match, keep as is (might be direct commit or already enriched)
      .
    end
  )
' "$LLM_OUTPUT" "$DB_RAW_DATA" > "$OUTPUT_FILE"

echo "✅ Enriched brag doc saved to: $OUTPUT_FILE"

