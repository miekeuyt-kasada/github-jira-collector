#!/bin/bash
# Migration: Add jira_ticket column to existing database

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/github_data.db"

if [ ! -f "$DB_PATH" ]; then
  echo "No database found at $DB_PATH - nothing to migrate"
  exit 0
fi

# Check if column already exists
has_column=$(sqlite3 "$DB_PATH" "PRAGMA table_info(prs)" | grep -c "jira_ticket")

if [ "$has_column" -gt 0 ]; then
  echo "✓ Column 'jira_ticket' already exists"
  exit 0
fi

echo "Adding jira_ticket column to prs table..."

sqlite3 "$DB_PATH" <<'EOF'
ALTER TABLE prs ADD COLUMN jira_ticket TEXT;
CREATE INDEX IF NOT EXISTS idx_prs_jira ON prs(jira_ticket);
EOF

echo "✅ Migration complete - jira_ticket column added"
echo "Note: Existing rows will have NULL for jira_ticket until PRs are re-cached"

