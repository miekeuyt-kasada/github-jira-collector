#!/bin/bash
# Migration: Add commit span columns to existing database

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/github_data.db"

if [ ! -f "$DB_PATH" ]; then
  echo "No database found at $DB_PATH - nothing to migrate"
  exit 0
fi

# Check if columns already exist
has_columns=$(sqlite3 "$DB_PATH" "PRAGMA table_info(prs)" | grep -c "commit_span")

if [ "$has_columns" -gt 0 ]; then
  echo "✓ Commit span columns already exist"
  exit 0
fi

echo "Adding commit span columns to prs table..."

sqlite3 "$DB_PATH" <<'EOF'
ALTER TABLE prs ADD COLUMN first_commit_date TEXT;
ALTER TABLE prs ADD COLUMN last_commit_date TEXT;
ALTER TABLE prs ADD COLUMN commit_span_seconds INTEGER;
ALTER TABLE prs ADD COLUMN commit_span_formatted TEXT;
EOF

echo "✅ Migration complete - commit span columns added"
echo "Note: Run reports again to populate commit span data for existing PRs"

