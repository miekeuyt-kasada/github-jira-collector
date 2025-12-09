#!/bin/bash
# Fix duplicate items in Postgres (same pr_id + month)
# Usage: ./fix_postgres_duplicates.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for connection string
POSTGRES_URL="${DATABASE_URL:-$POSTGRES_URL}"

if [ -z "$POSTGRES_URL" ]; then
  echo "❌ Error: DATABASE_URL or POSTGRES_URL environment variable not set"
  exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "Fixing duplicate items in Postgres"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check for duplicates
echo "→ Checking for duplicates..."
DUPLICATES=$(psql "$POSTGRES_URL" -t -c "
  SELECT pr_id, month, COUNT(*) as cnt
  FROM brag_items 
  WHERE pr_id IS NOT NULL
  GROUP BY pr_id, month
  HAVING COUNT(*) > 1;
" 2>/dev/null)

if [ -z "$DUPLICATES" ] || [ "$(echo "$DUPLICATES" | wc -l | tr -d ' ')" -eq 0 ]; then
  echo "  ✅ No duplicates found"
  exit 0
fi

echo "  Found duplicates:"
echo "$DUPLICATES" | while read -r line; do
  if [ -n "$line" ]; then
    pr_id=$(echo "$line" | awk '{print $1}')
    month=$(echo "$line" | awk '{print $2}')
    count=$(echo "$line" | awk '{print $3}')
    echo "    PR $pr_id in $month: $count items"
  fi
done

echo ""
echo "→ Fixing duplicates (keeping the most recently updated item)..."

# For each duplicate group, keep the one with the latest updated_at
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 <<'EOF'
-- Delete duplicates, keeping the one with the latest updated_at
WITH ranked_items AS (
  SELECT id,
    pr_id,
    month,
    updated_at,
    ROW_NUMBER() OVER (
      PARTITION BY pr_id, month 
      ORDER BY updated_at DESC, id DESC
    ) as rn
  FROM brag_items
  WHERE pr_id IS NOT NULL
)
DELETE FROM brag_items
WHERE id IN (
  SELECT id FROM ranked_items WHERE rn > 1
);
EOF

deleted=$(psql "$POSTGRES_URL" -t -c "SELECT COUNT(*) FROM (SELECT pr_id, month, COUNT(*) as cnt FROM brag_items WHERE pr_id IS NOT NULL GROUP BY pr_id, month HAVING COUNT(*) > 1) as dup;" 2>/dev/null | tr -d ' ')

if [ "$deleted" = "0" ]; then
  echo "  ✅ Duplicates removed"
else
  echo "  ⚠️  Some duplicates may still exist"
fi

echo ""
echo "→ Verifying unique constraint exists..."

# Ensure the unique index exists
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 <<'EOF'
CREATE UNIQUE INDEX IF NOT EXISTS idx_brag_items_pr_month 
  ON brag_items(pr_id, month) WHERE pr_id IS NOT NULL;
EOF

echo "  ✅ Unique constraint verified"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Fix complete!"
echo "════════════════════════════════════════════════════════════════"


