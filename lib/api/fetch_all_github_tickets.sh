#!/bin/bash
# Fetch Jira metadata for all tickets referenced in GitHub PRs
# Usage: ./fetch_all_github_tickets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_DB="$SCRIPT_DIR/../.cache/github_data.db"

# Check if GitHub database exists
if [ ! -f "$GITHUB_DB" ]; then
  echo "❌ Error: GitHub database not found at $GITHUB_DB" >&2
  echo "Run the GitHub data collection scripts first." >&2
  exit 1
fi

# Check Jira environment
if [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_BASE_URL:-}" ]; then
  echo "❌ Error: Required Jira environment variables not set" >&2
  echo "Please set: JIRA_EMAIL, JIRA_API_TOKEN, JIRA_BASE_URL" >&2
  echo "Run: source .env.local && export JIRA_EMAIL JIRA_API_TOKEN JIRA_BASE_URL" >&2
  exit 1
fi

echo "🎫 Extracting Jira tickets from GitHub database..."

# Get all unique ticket numbers from PRs
tickets=$(sqlite3 "$GITHUB_DB" "
  SELECT DISTINCT jira_ticket 
  FROM prs 
  WHERE jira_ticket IS NOT NULL 
    AND jira_ticket != '' 
  ORDER BY jira_ticket
")

if [ -z "$tickets" ]; then
  echo "❌ No Jira tickets found in GitHub database" >&2
  exit 1
fi

ticket_count=$(echo "$tickets" | wc -l | tr -d ' ')
echo "Found $ticket_count unique tickets"
echo ""

# Convert to array for batch processing
ticket_array=($tickets)

# Fetch tickets in batches of 10 (to avoid overwhelming the API)
batch_size=10
total_batches=$(( (ticket_count + batch_size - 1) / batch_size ))

echo "Fetching in $total_batches batches..."
echo ""

for ((i=0; i<${#ticket_array[@]}; i+=batch_size)); do
  batch_num=$(( i / batch_size + 1 ))
  batch=("${ticket_array[@]:i:batch_size}")
  
  echo "Batch $batch_num/$total_batches (${#batch[@]} tickets)..."
  
  # Fetch this batch
  "$SCRIPT_DIR/get_jira_ticket.sh" "${batch[@]}" > /dev/null
  
  # Small delay between batches to be nice to the API
  if [ $i -lt $((${#ticket_array[@]} - batch_size)) ]; then
    sleep 1
  fi
done

echo ""
echo "✅ Done! Fetched metadata for $ticket_count tickets"
echo ""
echo "Tickets are cached in: $SCRIPT_DIR/../.cache/jira_tickets.db"
