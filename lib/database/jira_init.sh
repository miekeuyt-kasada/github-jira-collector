#!/bin/bash
# Initialize SQLite database for Jira ticket caching
# Usage: ./jira_init.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/jira_tickets.db"

mkdir -p "$CACHE_DIR"

sqlite3 "$DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS jira_tickets (
  ticket_key TEXT PRIMARY KEY,
  summary TEXT,
  description TEXT,
  status TEXT,
  issue_type TEXT,
  assignee TEXT,
  assignee_id TEXT,
  reporter TEXT,
  reporter_id TEXT,
  priority TEXT,
  epic_key TEXT,
  epic_name TEXT,
  epic_title TEXT,
  parent_key TEXT,
  capex_opex TEXT,
  labels TEXT,
  resolution TEXT,
  story_points REAL,
  chapter TEXT,
  service TEXT,
  created_at TEXT,
  updated_at TEXT,
  resolved_at TEXT,
  fetched_at TEXT,
  is_closed INTEGER
);

CREATE INDEX IF NOT EXISTS idx_jira_epic ON jira_tickets(epic_key);
CREATE INDEX IF NOT EXISTS idx_jira_parent ON jira_tickets(parent_key);
CREATE INDEX IF NOT EXISTS idx_jira_status ON jira_tickets(status);
CREATE INDEX IF NOT EXISTS idx_jira_labels ON jira_tickets(labels);
CREATE INDEX IF NOT EXISTS idx_jira_closed ON jira_tickets(is_closed);
EOF

echo "✅ Jira tickets database initialized: $DB_PATH"
