#!/bin/bash
# Backfill first_commit_sha for existing items
# Usage: ./migrate_backfill_commit_shas.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"

# Source the helper functions
source "$DB_HELPERS"

echo "════════════════════════════════════════════════════════════════"
echo "Backfilling first_commit_sha from raw data"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
  echo "⚠️  Database not found at: $DB_PATH"
  exit 1
fi

# Find .temp directory
TEMP_DIR="$(cd "$MIGRATION_SCRIPT_DIR/../../../.." && pwd)/.temp"

if [ ! -d "$TEMP_DIR" ]; then
  echo "⚠️  .temp directory not found at: $TEMP_DIR"
  exit 1
fi

echo "→ Scanning for raw data files in: $TEMP_DIR"
echo ""

# Find all month-*-raw.json files
RAW_FILES=$(find "$TEMP_DIR" -name "month-*-raw.json" | sort)

if [ -z "$RAW_FILES" ]; then
  echo "⚠️  No raw JSON files found"
  exit 0
fi

TOTAL_UPDATED=0
TOTAL_SKIPPED=0

for file in $RAW_FILES; do
  filename=$(basename "$file")
  month=$(echo "$filename" | sed -E 's/month-([0-9]{4}-[0-9]{2})-raw\.json/\1/')
  
  if [ "$month" = "$filename" ]; then
    echo "⚠️  Could not extract month from: $filename"
    continue
  fi
  
  echo "→ Processing $month from $filename..."
  
  # Extract PRs with their first commit SHA
  jq -r '.prs[] | "\(.pr_number)|\(.commits[0].sha // "")"' "$file" | while IFS='|' read -r pr_number first_sha; do
    if [ -z "$first_sha" ] || [ "$first_sha" = "null" ]; then
      continue
    fi
    
    # Check if item exists and needs updating
    existing=$(sqlite3 "$DB_PATH" "SELECT id, first_commit_sha FROM brag_items WHERE pr_id=$pr_number" 2>/dev/null)
    
    if [ -n "$existing" ]; then
      item_id=$(echo "$existing" | cut -d'|' -f1)
      current_sha=$(echo "$existing" | cut -d'|' -f2)
      
      if [ -z "$current_sha" ] || [ "$current_sha" = "" ]; then
        # Update with SHA
        sqlite3 "$DB_PATH" "UPDATE brag_items SET first_commit_sha='$first_sha' WHERE id=$item_id;" 2>/dev/null
        if [ $? -eq 0 ]; then
          echo "  ✅ Updated PR $pr_number (ID: $item_id) with SHA: ${first_sha:0:8}..."
          TOTAL_UPDATED=$((TOTAL_UPDATED + 1))
        fi
      else
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
      fi
    fi
  done
  
  echo ""
done

echo "════════════════════════════════════════════════════════════════"
echo "Backfill complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Get final stats
items_with_sha=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM brag_items WHERE first_commit_sha IS NOT NULL" 2>/dev/null)
items_without_sha=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM brag_items WHERE first_commit_sha IS NULL" 2>/dev/null)
total_items=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM brag_items" 2>/dev/null)

echo "Summary:"
echo "  Items with first_commit_sha: $items_with_sha"
echo "  Items without first_commit_sha: $items_without_sha"
echo "  Total items: $total_items"
echo ""
echo "✅ Backfill successful"



