#!/bin/bash
# Backfill state column from github_report.db
# Usage: ./migrate_backfill_state.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"

# Source the helper functions to get DB_PATH
source "$DB_HELPERS"

# Get the cache directory from DB_PATH
CACHE_DIR="$(dirname "$DB_PATH")"
BRAGDOC_DB="$DB_PATH"
GITHUB_DB="$CACHE_DIR/github_report.db"

echo "════════════════════════════════════════════════════════════════"
echo "Backfilling state from github_report.db"
echo "════════════════════════════════════════════════════════════════"
echo ""

if [ ! -f "$GITHUB_DB" ]; then
  echo "⚠️  github_report.db not found at: $GITHUB_DB"
  exit 1
fi

if [ ! -f "$BRAGDOC_DB" ]; then
  echo "⚠️  bragdoc_items.db not found at: $BRAGDOC_DB"
  exit 1
fi

echo "→ Updating state for items with pr_id..."

TOTAL_UPDATED=0

# Get all items that need state backfilled
sqlite3 "$BRAGDOC_DB" "SELECT DISTINCT pr_id FROM brag_items WHERE pr_id IS NOT NULL AND state IS NULL;" | while read -r pr_id; do
  # Get state from github_report.db
  state=$(sqlite3 "$GITHUB_DB" "SELECT state FROM prs WHERE pr_number=$pr_id LIMIT 1;" 2>/dev/null)
  
  if [ -n "$state" ] && [ "$state" != "" ]; then
    # Update all items with this pr_id
    sqlite3 "$BRAGDOC_DB" "UPDATE brag_items SET state='$state' WHERE pr_id=$pr_id AND state IS NULL;" 2>/dev/null
    if [ $? -eq 0 ]; then
      count=$(sqlite3 "$BRAGDOC_DB" "SELECT COUNT(*) FROM brag_items WHERE pr_id=$pr_id AND state='$state';" 2>/dev/null)
      echo "  ✅ Updated PR $pr_id → state: $state ($count items)"
      TOTAL_UPDATED=$((TOTAL_UPDATED + count))
    fi
  fi
done

updated=$(sqlite3 "$BRAGDOC_DB" "SELECT COUNT(*) FROM brag_items WHERE state IS NOT NULL;" 2>/dev/null)
total=$(sqlite3 "$BRAGDOC_DB" "SELECT COUNT(*) FROM brag_items;" 2>/dev/null)
null_state=$(sqlite3 "$BRAGDOC_DB" "SELECT COUNT(*) FROM brag_items WHERE state IS NULL;" 2>/dev/null)

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Backfill complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  - Items with state: $updated"
echo "  - Items without state: $null_state"
echo "  - Total items: $total"
echo ""

