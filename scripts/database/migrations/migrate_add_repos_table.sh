#!/bin/bash
# Migration: Add repos table for interval-based caching
# Usage: ./migrate_add_repos_table.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../../.cache"
DB_PATH="$CACHE_DIR/github_report.db"

mkdir -p "$CACHE_DIR"

echo "Running migration: Add repos table..."

sqlite3 "$DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS repos (
  username TEXT NOT NULL,
  since_date TEXT NOT NULL,
  repo_name TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  PRIMARY KEY (username, since_date, repo_name)
);

CREATE INDEX IF NOT EXISTS idx_repos_lookup ON repos(username, since_date);
EOF

echo "✅ Migration complete: repos table added"

