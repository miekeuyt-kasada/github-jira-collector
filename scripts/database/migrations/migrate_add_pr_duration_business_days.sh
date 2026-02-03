#!/bin/bash
# Migration: Add PR duration business days column to existing database

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/github_data.db"

if [ ! -f "$DB_PATH" ]; then
  echo "No database found at $DB_PATH - nothing to migrate"
  exit 0
fi

# Check if column already exists
has_column=$(sqlite3 "$DB_PATH" "PRAGMA table_info(prs)" | grep -c "duration_business_days")

if [ "$has_column" -gt 0 ]; then
  echo "✓ Column 'duration_business_days' already exists"
  exit 0
fi

echo "Adding duration_business_days column to prs table..."

sqlite3 "$DB_PATH" <<'EOF'
ALTER TABLE prs ADD COLUMN duration_business_days INTEGER;
EOF

echo "✅ Migration complete - duration_business_days column added"
echo "Note: Run reports again to populate PR duration business days data"

