#!/bin/bash
# Migrate from first_commit_sha to commit_shas array
# Usage: ./migrate_sha_to_array.sh

MIGRATION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HELPERS="$MIGRATION_SCRIPT_DIR/../bragdoc_db_helpers.sh"
source "$DB_HELPERS"

echo "════════════════════════════════════════════════════════════════"
echo "Migration: Convert first_commit_sha to commit_shas array"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Drop unique indexes on pr_id, ticket_no, and first_commit_sha
echo "→ Dropping unique indexes..."
sqlite3 "$DB_PATH" "DROP INDEX IF EXISTS idx_brag_items_pr_id_unique;" 2>/dev/null
sqlite3 "$DB_PATH" "DROP INDEX IF EXISTS idx_brag_items_ticket_no_unique;" 2>/dev/null
sqlite3 "$DB_PATH" "DROP INDEX IF EXISTS idx_brag_items_first_commit_sha_unique;" 2>/dev/null
echo "  ✅ Unique indexes dropped (allows multiple achievements per PR)"

# Rename column
echo ""
echo "→ Renaming first_commit_sha to commit_shas..."
sqlite3 "$DB_PATH" <<'EOF'
ALTER TABLE brag_items RENAME COLUMN first_commit_sha TO commit_shas;
EOF
echo "  ✅ Column renamed"

# Convert existing single SHAs to arrays
echo ""
echo "→ Converting existing SHAs to JSON arrays..."
sqlite3 "$DB_PATH" <<'EOF'
UPDATE brag_items 
SET commit_shas = json_array(commit_shas) 
WHERE commit_shas IS NOT NULL AND commit_shas NOT LIKE '[%';
EOF
echo "  ✅ Converted to arrays"

# Create regular (non-unique) index
echo ""
echo "→ Creating index on commit_shas..."
sqlite3 "$DB_PATH" "CREATE INDEX IF NOT EXISTS idx_brag_items_commit_shas ON brag_items(commit_shas);" 2>/dev/null
echo "  ✅ Index created"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Migration complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""

total=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM brag_items" 2>/dev/null)
with_shas=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM brag_items WHERE commit_shas IS NOT NULL" 2>/dev/null)

echo "Summary:"
echo "  Total items: $total"
echo "  Items with commit_shas: $with_shas"
echo ""
echo "✅ Schema updated successfully"

