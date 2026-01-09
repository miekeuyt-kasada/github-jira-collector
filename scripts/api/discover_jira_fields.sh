#!/bin/bash
# Discover Jira custom field IDs by harvesting from real issues in your github database
# Usage: ./discover_jira_fields.sh [limit]
#   limit: optional, number of issues to sample (default: 5)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# LIMIT="${1:-5}"
LIMIT=1000

# Find the github_report.db
DB_PATH="$SCRIPT_DIR/../../github-summary/.cache/github_report.db"
if [ ! -f "$DB_PATH" ]; then
  DB_PATH="$SCRIPT_DIR/../.cache/github_report.db"
fi

if [ ! -f "$DB_PATH" ]; then
  echo "❌ Error: github_report.db not found" >&2
  echo "   Expected at: github-summary/.cache/github_report.db" >&2
  echo "" >&2
  echo "Run this from your project root, or ensure the database exists." >&2
  exit 1
fi

echo "🔍 Discovering Jira custom fields from your PRs..."
echo ""

# Run the harvest script
"$SCRIPT_DIR/harvest_jira_custom_fields.sh" "$DB_PATH" "$LIMIT"
