#!/bin/bash
# Re-enrich existing interpreted data and persist to database
# Usage: ./reenrich_and_persist.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"
ENRICH_SCRIPT="$MIGRATION_SCRIPT_DIR/../../compose/enrich_bragdoc.sh"

source "$DB_HELPERS"

TEMP_DIR="$(cd "$MIGRATION_SCRIPT_DIR/../../../.." && pwd)/.temp"

echo "Re-enriching and persisting months: 08, 10, 11"
echo ""

for month in 08 10 11; do
  interpreted="$TEMP_DIR/month-2025-$month-interpreted.json"
  raw="$TEMP_DIR/month-2025-$month-raw.json"
  enriched="/tmp/enriched-2025-$month.json"
  
  echo "→ Processing 2025-$month..."
  
  # Enrich
  "$ENRICH_SCRIPT" "$interpreted" "$raw" "$enriched" >/dev/null
  
  # Persist
  temp_items=$(mktemp)
  jq -c '.[]' "$enriched" > "$temp_items" 2>/dev/null
  
  while IFS= read -r item; do
    [ -n "$item" ] && insert_brag_item "$item" "2025-$month" >/dev/null 2>&1
  done < "$temp_items"
  
  rm -f "$temp_items"
  
  count=$(get_month_item_count "2025-$month")
  echo "  ✅ $count items in database"
done

echo ""
echo "Final stats:"
sqlite3 "$DB_PATH" "SELECT 'Items with SHA: ' || COUNT(*) FROM brag_items WHERE first_commit_sha IS NOT NULL; SELECT 'Total items: ' || COUNT(*) FROM brag_items;"



