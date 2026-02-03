#!/bin/bash
# Fix corrupted dates in bragdoc items database
# Dates that are stored as arrays of JSON strings need to be flattened

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/bragdoc_items.db"

if [ ! -f "$DB_PATH" ]; then
  echo "❌ Error: Database not found at $DB_PATH"
  exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "Fixing corrupted dates in bragdoc items"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Get all items with dates
temp_file=$(mktemp)
sqlite3 "$DB_PATH" -json "SELECT id, dates FROM brag_items WHERE dates IS NOT NULL" > "$temp_file" 2>/dev/null

fixed_count=0

while IFS= read -r item_json; do
  if [ -z "$item_json" ]; then
    continue
  fi
  
  id=$(echo "$item_json" | jq -r '.id')
  dates_raw=$(echo "$item_json" | jq -r '.dates')
  
  # Parse the dates field (it might be a JSON string or already parsed)
  dates=$(echo "$dates_raw" | jq -c '.')
  
  # Check if dates is an array of strings that look like JSON arrays
  if echo "$dates" | jq -e 'type == "array" and length > 0 and (.[0] | type) == "string" and (.[0] | startswith("["))' >/dev/null 2>&1; then
    # This is corrupted - flatten it
    fixed_dates=$(echo "$dates" | jq -c 'map(if type == "string" and startswith("[") then (fromjson? // .) else . end) | flatten | unique')
    
    # Update the database
    sqlite3 "$DB_PATH" <<SQL
UPDATE brag_items SET dates = json('$fixed_dates') WHERE id = $id;
SQL
    
    fixed_count=$((fixed_count + 1))
    echo "  Fixed dates for item $id: $dates -> $fixed_dates"
  fi
done < <(jq -c '.[]' "$temp_file" 2>/dev/null)

rm -f "$temp_file"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Date fix complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  Items fixed: $fixed_count"
echo ""
echo "✅ Dates fixed"

