#!/bin/bash
# Add first_commit_sha column for tertiary deduplication
# Usage: ./migrate_add_first_commit_sha.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"
DB_INIT="$MIGRATION_SCRIPT_DIR/../bragdoc_db_init.sh"

# Source the helper functions
source "$DB_HELPERS"

echo "════════════════════════════════════════════════════════════════"
echo "Migration: Add first_commit_sha column"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
  echo "⚠️  Database not found. Run bragdoc_db_init.sh first."
  exit 1
fi

echo "→ Adding first_commit_sha column..."

# Add column if it doesn't exist
sqlite3 "$DB_PATH" <<'EOF'
-- Add column (SQLite allows this even if column exists, but will error)
ALTER TABLE brag_items ADD COLUMN first_commit_sha TEXT;
EOF

if [ $? -eq 0 ]; then
  echo "  ✅ Column added successfully"
else
  echo "  ℹ️  Column may already exist, continuing..."
fi

echo ""
echo "→ Creating partial unique index on first_commit_sha..."

sqlite3 "$DB_PATH" <<'EOF'
CREATE UNIQUE INDEX IF NOT EXISTS idx_brag_items_first_commit_sha_unique 
  ON brag_items(first_commit_sha) 
  WHERE first_commit_sha IS NOT NULL;
EOF

echo "  ✅ Index created"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Migration complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  - Added first_commit_sha TEXT column"
echo "  - Created partial unique index for deduplication"
echo "  - Total items in database: $(get_item_count)"
echo ""
echo "Note: Existing items have NULL first_commit_sha."
echo "      Run brag doc generation to populate SHAs going forward."



