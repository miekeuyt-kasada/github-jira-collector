#!/bin/bash
# Add jira_ticket_history table for caching JIRA changelog
# Usage: ./migrate_add_jira_history.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../../.cache"
DB_PATH="$CACHE_DIR/jira_tickets.db"

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
  echo "❌ Error: JIRA tickets database not found: $DB_PATH"
  echo "   Run jira_init.sh first"
  exit 1
fi

echo "Adding jira_ticket_history table..."

sqlite3 "$DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS jira_ticket_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_key TEXT NOT NULL,
  field_name TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT NOT NULL,
  changed_by TEXT,
  fetched_at TEXT DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(ticket_key, field_name, changed_at)
);

CREATE INDEX IF NOT EXISTS idx_jira_history_ticket ON jira_ticket_history(ticket_key);
CREATE INDEX IF NOT EXISTS idx_jira_history_field ON jira_ticket_history(field_name);
CREATE INDEX IF NOT EXISTS idx_jira_history_changed ON jira_ticket_history(changed_at);
EOF

if [ $? -eq 0 ]; then
  echo "✅ JIRA history table created successfully"
  
  # Show current table info
  echo ""
  echo "Database tables:"
  sqlite3 "$DB_PATH" ".tables"
  
  echo ""
  echo "History table schema:"
  sqlite3 "$DB_PATH" ".schema jira_ticket_history"
else
  echo "❌ Error creating history table"
  exit 1
fi
