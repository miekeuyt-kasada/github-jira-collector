#!/bin/bash
# Migration: Add business days column to existing database

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/github_data.db"

if [ ! -f "$DB_PATH" ]; then
  echo "No database found at $DB_PATH - nothing to migrate"
  exit 0
fi

# Check if column already exists
has_column=$(sqlite3 "$DB_PATH" "PRAGMA table_info(prs)" | grep -c "commit_span_business_days")

if [ "$has_column" -gt 0 ]; then
  echo "✓ Column 'commit_span_business_days' already exists"
  exit 0
fi

echo "Adding commit_span_business_days column to prs table..."

sqlite3 "$DB_PATH" <<'EOF'
ALTER TABLE prs ADD COLUMN commit_span_business_days INTEGER;
EOF

echo "✅ Migration complete - commit_span_business_days column added"
echo "Note: Run reports again to populate business days data for existing PRs"

