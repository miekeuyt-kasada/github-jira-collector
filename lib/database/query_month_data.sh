#!/bin/bash
# Query GitHub data from database for a specific date range
# Usage: ./query_month_data.sh [--username <username>] <start_date> <end_date>
# Examples:
#   ./query_month_data.sh --username miekeuyt-kasada 2025-07-01 2025-08-01
#   ./query_month_data.sh 2025-07-01 2025-08-01  # Uses GITHUB_USERNAME env var

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/github_data.db"

# Load environment variables from .env.local if it exists
if [ -f "$SCRIPT_DIR/../.env.local" ]; then
  source "$SCRIPT_DIR/../.env.local"
fi

if [ ! -f "$DB_PATH" ]; then
  echo "Error: Database not found at $DB_PATH" >&2
  echo "Run ./db_init.sh first" >&2
  exit 1
fi

# Parse flags
USERNAME=""
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --username)
      USERNAME="$2"
      shift 2
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# Use provided username or fall back to env var
USERNAME=${USERNAME:-${GITHUB_USERNAME:-}}

if [ -z "$USERNAME" ]; then
  echo "Error: GitHub username not provided" >&2
  echo "Usage: $0 [--username <username>] <start_date> <end_date>" >&2
  echo "  Provide --username flag or set GITHUB_USERNAME environment variable" >&2
  exit 1
fi

DATE_START=$(echo "${POSITIONAL_ARGS[0]:-}" | tr '/' '-')
DATE_END=$(echo "${POSITIONAL_ARGS[1]:-}" | tr '/' '-')

if [ -z "$DATE_START" ] || [ -z "$DATE_END" ]; then
  echo "Usage: $0 [--username <username>] <start_date> <end_date>" >&2
  echo "Example: $0 --username miekeuyt 2025-07-01 2025-08-01" >&2
  echo "         $0 2025-07-01 2025-08-01  # Uses GITHUB_USERNAME env var" >&2
  exit 1
fi

# Query PRs and their commits and output as clean JSON
sqlite3 "$DB_PATH" <<EOF | jq -r '.[0].result'
.mode json
SELECT json_object(
  'prs', (
    SELECT json_group_array(
      json_object(
        'pr_number', pr_number,
        'repo', repo,
        'title', title,
        'description', description,
        'state', state,
        'merged_at', merged_at,
        'closed_at', closed_at,
        'created_at', created_at,
        'jira_ticket', jira_ticket,
        'first_commit_date', first_commit_date,
        'last_commit_date', last_commit_date,
        'commits', (
          SELECT json_group_array(
            json_object(
              'sha', sha,
              'message', message,
              'date', date,
              'author', author
            )
          )
          FROM pr_commits pc
          WHERE pc.repo = prs.repo 
            AND pc.pr_number = prs.pr_number
          ORDER BY pc.date ASC
        )
      )
    )
    FROM prs
    WHERE created_at >= '$DATE_START' 
      AND created_at < '$DATE_END'
  ),
  'direct_commits', (
    SELECT json_group_array(
      json_object(
        'sha', sha,
        'repo', repo,
        'message', message,
        'date', date,
        'author', author
      )
    )
    FROM direct_commits
    WHERE date >= '$DATE_START' 
      AND date < '$DATE_END'
      AND author = '$USERNAME'
    ORDER BY date ASC
  )
) as result;
EOF

