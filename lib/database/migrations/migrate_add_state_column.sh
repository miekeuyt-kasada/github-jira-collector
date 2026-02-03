#!/bin/bash
# Add state column to track PR state (open, closed, merged)
# Usage: ./migrate_add_state_column.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"

# Source the helper functions
source "$DB_HELPERS"

echo "════════════════════════════════════════════════════════════════"
echo "Migration: Add state column"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
  echo "⚠️  Database not found. Run bragdoc_db_init.sh first."
  exit 1
fi

echo "→ Adding state column..."

# Add column if it doesn't exist
sqlite3 "$DB_PATH" <<'EOF'
-- Add column (SQLite allows this even if column exists, but will error)
ALTER TABLE brag_items ADD COLUMN state TEXT;
EOF

if [ $? -eq 0 ]; then
  echo "  ✅ Column added successfully"
else
  echo "  ℹ️  Column may already exist, continuing..."
fi

echo ""
echo "→ Creating index on state..."

sqlite3 "$DB_PATH" <<'EOF'
CREATE INDEX IF NOT EXISTS idx_brag_items_state ON brag_items(state);
EOF

echo "  ✅ Index created"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Migration complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  - Added state TEXT column"
echo "  - Created index on state for querying"
echo "  - Total items in database: $(get_item_count)"
echo ""
echo "Note: Existing items have NULL state."
echo "      Run brag doc generation to populate state going forward."


