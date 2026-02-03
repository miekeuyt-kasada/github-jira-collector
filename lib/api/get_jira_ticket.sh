#!/bin/bash
# Fetch Jira ticket metadata from Jira Cloud REST API v3
# Usage: ./get_jira_ticket.sh TICKET_KEY [TICKET_KEY...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_DIR="$SCRIPT_DIR/../database"

# Source helper functions
source "$DB_DIR/jira_helpers.sh"

# Load environment variables from .env.local if it exists
if [ -f "$SCRIPT_DIR/../../.env.local" ]; then
  source "$SCRIPT_DIR/../../.env.local"
fi

# Check required environment variables
if [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_BASE_URL:-}" ]; then
  echo "❌ Error: Required Jira environment variables not set" >&2
  echo "Please set: JIRA_EMAIL, JIRA_API_TOKEN, JIRA_BASE_URL" >&2
  exit 1
fi

# Default custom fields if not set
JIRA_EPIC_FIELD="${JIRA_EPIC_FIELD:-customfield_10009}"
JIRA_EPIC_NAME_FIELD="${JIRA_EPIC_NAME_FIELD:-customfield_10008}"
JIRA_SPRINT_FIELD="${JIRA_SPRINT_FIELD:-customfield_10007}"
JIRA_STORY_POINTS_FIELD="${JIRA_STORY_POINTS_FIELD:-customfield_11004}"
JIRA_CHAPTER_FIELD="${JIRA_CHAPTER_FIELD:-customfield_11782}"
JIRA_CHAPTER_ALT_FIELD="${JIRA_CHAPTER_ALT_FIELD:-customfield_12384}"
JIRA_SERVICE_FIELD="${JIRA_SERVICE_FIELD:-customfield_11783}"
JIRA_SERVICE_ALT_FIELD="${JIRA_SERVICE_ALT_FIELD:-customfield_12383}"
JIRA_CAPEX_OPEX_FIELD="${JIRA_CAPEX_OPEX_FIELD:-customfield_11280}"

# Create auth header
AUTH_HEADER="Authorization: Basic $(echo -n "$JIRA_EMAIL:$JIRA_API_TOKEN" | base64)"

# Fields to fetch
FIELDS="summary,description,status,issuetype,assignee,reporter,priority,parent,labels,resolution,created,updated,resolutiondate,$JIRA_EPIC_FIELD,$JIRA_EPIC_NAME_FIELD,$JIRA_SPRINT_FIELD,$JIRA_STORY_POINTS_FIELD,$JIRA_CHAPTER_FIELD,$JIRA_CHAPTER_ALT_FIELD,$JIRA_SERVICE_FIELD,$JIRA_SERVICE_ALT_FIELD,$JIRA_CAPEX_OPEX_FIELD"

# Fetch a single ticket
fetch_ticket() {
  local ticket_key=$1
  
  # Check if already cached with TTL
  local ticket_cached=false
  if is_jira_cached_with_ttl "$ticket_key" 24; then
    echo "  ✓ $ticket_key (cached)" >&2
    ticket_cached=true
  else
    echo "  → Fetching $ticket_key from Jira..." >&2
    
    # Fetch from API
    response=$(curl -s -X GET \
      "$JIRA_BASE_URL/rest/api/3/issue/$ticket_key?fields=$FIELDS" \
      -H "Accept: application/json" \
      -H "$AUTH_HEADER")
    
    # Check for errors
    if echo "$response" | jq -e '.errorMessages' > /dev/null 2>&1; then
      echo "  ✗ Error fetching $ticket_key:" >&2
      echo "$response" | jq -r '.errorMessages[]' >&2
      return 1
    fi
    
    # Cache the ticket
    cache_jira_ticket "$response"
    echo "  ✓ $ticket_key (fetched)" >&2
  fi
  
  # Fetch history if not cached (for both newly fetched and previously cached tickets)
  # This handles tickets cached before history table existed
  if ! is_jira_history_cached "$ticket_key"; then
    echo "  → Fetching changelog for $ticket_key..." >&2
    changelog=$(curl -s -X GET \
      "$JIRA_BASE_URL/rest/api/3/issue/$ticket_key?expand=changelog&fields=none" \
      -H "Accept: application/json" \
      -H "$AUTH_HEADER")
    
    cache_jira_history "$ticket_key" "$changelog"
    echo "  ✓ Changelog cached" >&2
  fi
  
  # Return cached version (normalized format)
  get_cached_jira_ticket "$ticket_key"
}

# Main execution
if [ $# -eq 0 ]; then
  echo "Usage: $0 TICKET_KEY [TICKET_KEY...]" >&2
  echo "Example: $0 VIS-454 VIS-455" >&2
  exit 1
fi

# Initialize database if it doesn't exist
if [ ! -f "$DB_DIR/../.cache/jira_tickets.db" ]; then
  echo "Initializing Jira tickets database..." >&2
  "$DB_DIR/jira_init.sh" >&2
fi

# Fetch all requested tickets
echo "Fetching Jira tickets..." >&2
results="[]"

for ticket_key in "$@"; do
  ticket_data=$(fetch_ticket "$ticket_key")
  if [ -n "$ticket_data" ] && [ "$ticket_data" != "null" ]; then
    results=$(echo "$results" | jq --argjson ticket "$ticket_data" '. + [$ticket]')
  fi
done

# Output results as JSON array
echo "$results"
