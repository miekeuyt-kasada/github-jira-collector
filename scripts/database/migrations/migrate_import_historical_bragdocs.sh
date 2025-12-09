#!/bin/bash
# Migrate historical brag doc items from .temp JSON files into database
# Usage: ./migrate_import_historical_bragdocs.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"
DB_INIT="$MIGRATION_SCRIPT_DIR/../bragdoc_db_init.sh"

# Source the helper functions
source "$DB_HELPERS"

# Initialize database if it doesn't exist
if [ ! -f "$DB_PATH" ]; then
  echo "→ Database not found, initializing..."
  "$DB_INIT"
fi

# Find all interpreted JSON files in .temp directory
# Go up from migrations -> database -> scripts -> github-summary -> root (4 levels)
TEMP_DIR="$(cd "$MIGRATION_SCRIPT_DIR/../../../.." && pwd)/.temp"

if [ ! -d "$TEMP_DIR" ]; then
  echo "Error: .temp directory not found at $TEMP_DIR" >&2
  exit 1
fi

echo "Scanning for historical brag doc files in: $TEMP_DIR"
echo ""

# Find all month-*-interpreted.json files
INTERPRETED_FILES=$(find "$TEMP_DIR" -name "month-*-interpreted.json" | sort)

if [ -z "$INTERPRETED_FILES" ]; then
  echo "⚠️  No interpreted JSON files found in $TEMP_DIR"
  exit 0
fi

TOTAL_IMPORTED=0
TOTAL_UPDATED=0
TOTAL_SKIPPED=0

for file in $INTERPRETED_FILES; do
  # Extract month from filename (e.g., month-2025-07-interpreted.json -> 2025-07)
  filename=$(basename "$file")
  month=$(echo "$filename" | sed -E 's/month-([0-9]{4}-[0-9]{2})-interpreted\.json/\1/')
  
  if [ "$month" = "$filename" ]; then
    echo "⚠️  Could not extract month from filename: $filename"
    continue
  fi
  
  echo "→ Processing $month from $filename..."
  
  # Check if file is empty or invalid JSON
  if [ ! -s "$file" ]; then
    echo "  ⚠️  File is empty, skipping"
    continue
  fi
  
  # Count items in file
  item_count=$(jq 'length' "$file" 2>/dev/null || echo "0")
  
  if [ "$item_count" -eq 0 ]; then
    echo "  ⚠️  No items found in file, skipping"
    continue
  fi
  
  echo "  Found $item_count items"
  
  # Import each item using a temp file to avoid subshell issues
  temp_items=$(mktemp)
  jq -c '.[]' "$file" > "$temp_items" 2>/dev/null
  
  while IFS= read -r item; do
    if [ -n "$item" ]; then
      insert_brag_item "$item" "$month" >/dev/null 2>&1
    fi
  done < "$temp_items"
  
  rm -f "$temp_items"
  
  # Get actual count from database for this month
  month_count=$(get_month_item_count "$month" 2>/dev/null || echo "0")
  
  echo "  ✅ Month $month: $month_count items in database"
  echo ""
  
  TOTAL_IMPORTED=$((TOTAL_IMPORTED + month_count))
done

echo "════════════════════════════════════════════════════════════════"
echo "Migration complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  Total items in database: $(get_item_count)"
echo "  Months imported: $(get_all_months | wc -l | tr -d ' ')"
echo ""

# Show breakdown by month
echo "Items by month:"
for month in $(get_all_months); do
  count=$(get_month_item_count "$month")
  echo "  $month: $count items"
done

echo ""
echo "✅ Historical brag doc data successfully migrated to database"

