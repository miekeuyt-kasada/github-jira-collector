#!/bin/bash
# Find which item exists locally but not in Postgres
# Usage: ./find_missing_item.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$SCRIPT_DIR/bragdoc_db_helpers.sh"
source "$DB_HELPERS"

# Check for connection string
POSTGRES_URL="${DATABASE_URL:-$POSTGRES_URL}"

if [ -z "$POSTGRES_URL" ]; then
  echo "❌ Error: DATABASE_URL or POSTGRES_URL environment variable not set"
  exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "Finding missing items"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "→ Getting local (pr_id, month) combinations..."
LOCAL_COMBOS=$(sqlite3 "$DB_PATH" "
  SELECT pr_id || '|' || month 
  FROM brag_items 
  WHERE pr_id IS NOT NULL 
  GROUP BY pr_id, month 
  ORDER BY month, pr_id;
" 2>/dev/null)

echo "→ Getting Postgres (pr_id, month) combinations..."
POSTGRES_COMBOS=$(psql "$POSTGRES_URL" -t -c "
  SELECT pr_id || '|' || month 
  FROM brag_items 
  WHERE pr_id IS NOT NULL 
  GROUP BY pr_id, month 
  ORDER BY month, pr_id;
" 2>/dev/null | tr -d ' ')

echo ""
echo "→ Comparing..."

# Find items in local but not in Postgres
MISSING=""
while IFS= read -r combo; do
  if [ -n "$combo" ]; then
    if ! echo "$POSTGRES_COMBOS" | grep -q "^$combo$"; then
      MISSING="$MISSING$combo\n"
    fi
  fi
done <<< "$LOCAL_COMBOS"

if [ -z "$MISSING" ]; then
  echo "  ✅ All local items are in Postgres"
else
  echo "  ⚠️  Missing items:"
  # Remove duplicates and process
  echo -e "$MISSING" | sort -u | while IFS='|' read -r pr_id month; do
    if [ -n "$pr_id" ] && [ -n "$month" ]; then
      achievement=$(sqlite3 "$DB_PATH" "SELECT achievement FROM brag_items WHERE pr_id=$pr_id AND month='$month' LIMIT 1;" 2>/dev/null)
      echo "    PR $pr_id in $month: ${achievement:0:60}..."
    fi
  done
fi

echo ""
echo "→ Checking items without pr_id..."

LOCAL_NO_PR=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM brag_items WHERE pr_id IS NULL;" 2>/dev/null)
POSTGRES_NO_PR=$(psql "$POSTGRES_URL" -t -c "SELECT COUNT(*) FROM brag_items WHERE pr_id IS NULL;" 2>/dev/null | tr -d ' ')

echo "  Local: $LOCAL_NO_PR items without pr_id"
echo "  Postgres: $POSTGRES_NO_PR items without pr_id"

if [ "$LOCAL_NO_PR" != "$POSTGRES_NO_PR" ]; then
  echo "  ⚠️  Mismatch in items without pr_id"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"

