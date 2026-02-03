#!/bin/bash
# Migration: Add epic and effort score columns to brag_items table
# Usage: ./migrate_add_epic_effort.sh
# Requires: DATABASE_URL environment variable set

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Source postgres helpers for connection test
POSTGRES_HELPERS="$SCRIPT_DIR/../postgres_helpers.sh"
if [ ! -f "$POSTGRES_HELPERS" ]; then
  echo "❌ Error: Postgres helpers not found: $POSTGRES_HELPERS"
  exit 1
fi

source "$POSTGRES_HELPERS"

# Validate DATABASE_URL is set
if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ Error: DATABASE_URL environment variable not set"
  echo ""
  echo "Set it with:"
  echo "  source .env.local && export DATABASE_URL"
  exit 1
fi

# Test connection
echo "→ Testing database connection..."
if ! pg_test_connection &>/dev/null; then
  echo "❌ Error: Cannot connect to Postgres database"
  echo "   Check your DATABASE_URL"
  exit 1
fi

echo "✓ Connected to database"

# Check if columns already exist
check_sql="SELECT column_name FROM information_schema.columns 
           WHERE table_name = 'brag_items' 
           AND column_name IN ('epic_key', 'epic_name', 'effort_score');"

existing_columns=$(psql "$DATABASE_URL" -t -c "$check_sql" 2>/dev/null | tr -d ' ' | grep -v '^$' || echo "")

if echo "$existing_columns" | grep -q "epic_key"; then
  echo "⚠️  Column epic_key already exists, skipping migration"
  echo "   If you need to re-run, manually drop columns first:"
  echo "   ALTER TABLE brag_items DROP COLUMN epic_key, DROP COLUMN epic_name, DROP COLUMN effort_score;"
  exit 0
fi

echo "→ Adding epic and effort score columns..."

# Run migration
migration_sql="
BEGIN;

-- Add new columns
ALTER TABLE brag_items 
  ADD COLUMN epic_key TEXT,
  ADD COLUMN epic_name TEXT,
  ADD COLUMN effort_score INTEGER;

-- Add index for efficient epic-based queries
CREATE INDEX idx_brag_epic ON brag_items(epic_key) WHERE epic_key IS NOT NULL;

-- Add index for effort score filtering (optional, if we use it for FE filtering)
CREATE INDEX idx_brag_effort ON brag_items(effort_score) WHERE effort_score IS NOT NULL;

COMMIT;
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<EOF
$migration_sql
EOF

if [ $? -eq 0 ]; then
  echo "✅ Migration completed successfully"
  echo ""
  echo "New columns added:"
  echo "  - epic_key (TEXT, nullable)"
  echo "  - epic_name (TEXT, nullable)"
  echo "  - effort_score (INTEGER, nullable)"
  echo ""
  echo "Indexes created:"
  echo "  - idx_brag_epic on epic_key"
  echo "  - idx_brag_effort on effort_score"
  echo ""
  echo "Next steps:"
  echo "  1. Run 04c_enrich_epic.sh to populate epic data for existing months"
  echo "  2. Re-run 05_persist_to_db.sh to update database records"
else
  echo "❌ Migration failed"
  exit 1
fi
