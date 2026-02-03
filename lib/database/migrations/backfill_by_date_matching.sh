#!/bin/bash
# Backfill by matching items to PRs via date overlap
# Usage: ./backfill_by_date_matching.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"

source "$DB_HELPERS"

TEMP_DIR="$(cd "$MIGRATION_SCRIPT_DIR/../../../.." && pwd)/.temp"

echo "════════════════════════════════════════════════════════════════"
echo "Backfilling by date matching"
echo "════════════════════════════════════════════════════════════════"
echo ""

for month in 08 10 11; do
  interpreted="$TEMP_DIR/month-2025-$month-interpreted.json"
  raw="$TEMP_DIR/month-2025-$month-raw.json"
  
  echo "→ Processing 2025-$month..."
  
  # For each item in interpreted data
  jq -c '.[]' "$interpreted" | while IFS= read -r item; do
    achievement=$(echo "$item" | jq -r '.achievement')
    dates=$(echo "$item" | jq -c '.dates // []')
    
    # Skip if no dates
    if [ "$dates" = "[]" ] || [ "$dates" = "null" ]; then
      continue
    fi
    
    start_date=$(echo "$dates" | jq -r '.[0] // empty')
    end_date=$(echo "$dates" | jq -r '.[-1] // empty')
    
    if [ -z "$start_date" ] || [ -z "$end_date" ]; then
      continue
    fi
    
    # Find matching PR in raw data by date overlap
    match=$(jq -r --arg start "$start_date" --arg end "$end_date" '
      .prs[] | 
      select(
        (.first_commit_date[0:10] >= $start and .first_commit_date[0:10] <= $end) or
        (.last_commit_date[0:10] >= $start and .last_commit_date[0:10] <= $end) or
        (.first_commit_date[0:10] <= $start and .last_commit_date[0:10] >= $end)
      ) | 
      "\(.pr_number)|\(.jira_ticket // "")|\(.commits[0].sha // "")"
    ' "$raw" | head -1)
    
    if [ -n "$match" ]; then
      pr_id=$(echo "$match" | cut -d'|' -f1)
      ticket_no=$(echo "$match" | cut -d'|' -f2)
      first_sha=$(echo "$match" | cut -d'|' -f3)
      
      # Update database items that match this achievement and date range
      sqlite3 "$DB_PATH" <<SQL
UPDATE brag_items 
SET pr_id = $pr_id,
    ticket_no = $([ -z "$ticket_no" ] && echo "NULL" || echo "'$ticket_no'"),
    first_commit_sha = $([ -z "$first_sha" ] && echo "NULL" || echo "'$first_sha'")
WHERE month = '2025-$month' 
  AND achievement = '$(echo "$achievement" | sed "s/'/''/g")'
  AND (pr_id IS NULL OR first_commit_sha IS NULL);
SQL
      
      if [ $? -eq 0 ]; then
        echo "  ✅ Matched: ${achievement:0:50}... → PR #$pr_id"
      fi
    fi
  done
  
  echo ""
done

echo "════════════════════════════════════════════════════════════════"
echo "Backfill complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""

sqlite3 "$DB_PATH" "SELECT 'Items with SHA: ' || COUNT(*) FROM brag_items WHERE first_commit_sha IS NOT NULL; SELECT 'Total items: ' || COUNT(*) FROM brag_items;"



