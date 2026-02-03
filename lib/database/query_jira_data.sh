#!/bin/bash
# Query JIRA data from database
# Usage: ./query_jira_data.sh [--ticket TICKET_KEY] [--epic EPIC_KEY] [--status STATUS]
# Examples:
#   ./query_jira_data.sh                           # All tickets as JSON
#   ./query_jira_data.sh --ticket VIS-454          # Specific ticket
#   ./query_jira_data.sh --epic VIS-98             # All tickets in epic
#   ./query_jira_data.sh --status "In Progress"    # All tickets by status

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/jira_tickets.db"

# Load environment variables from .env.local if it exists
if [ -f "$SCRIPT_DIR/../../.env.local" ]; then
  source "$SCRIPT_DIR/../../.env.local"
fi

if [ ! -f "$DB_PATH" ]; then
  echo "Error: Database not found at $DB_PATH" >&2
  echo "Run ./get_jira_data.sh first" >&2
  exit 1
fi

# Parse flags
TICKET_KEY=""
EPIC_KEY=""
STATUS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --ticket)
      TICKET_KEY="$2"
      shift 2
      ;;
    --epic)
      EPIC_KEY="$2"
      shift 2
      ;;
    --status)
      STATUS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--ticket KEY] [--epic KEY] [--status STATUS]" >&2
      exit 1
      ;;
  esac
done

# Build WHERE clause
WHERE_CLAUSES=()
if [ -n "$TICKET_KEY" ]; then
  WHERE_CLAUSES+=("ticket_key='$TICKET_KEY'")
fi
if [ -n "$EPIC_KEY" ]; then
  WHERE_CLAUSES+=("epic_key='$EPIC_KEY'")
fi
if [ -n "$STATUS" ]; then
  WHERE_CLAUSES+=("status='$STATUS'")
fi

# Construct WHERE clause
WHERE=""
if [ ${#WHERE_CLAUSES[@]} -gt 0 ]; then
  WHERE="WHERE $(IFS=' AND '; echo "${WHERE_CLAUSES[*]}")"
fi

# Query and output as JSON
sqlite3 "$DB_PATH" <<EOF | jq '.'
.mode json
SELECT * FROM jira_tickets $WHERE ORDER BY ticket_key;
EOF
