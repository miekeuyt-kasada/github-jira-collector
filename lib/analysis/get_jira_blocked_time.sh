#!/bin/bash
# Get blocked time for a JIRA ticket during a specific date range
# Usage: ./get_jira_blocked_time.sh TICKET_KEY START_DATE END_DATE
# Returns: Number of days ticket was in blocked status during the period

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_DIR="$SCRIPT_DIR/../database"

# Source helper functions
source "$DB_DIR/jira_helpers.sh"

if [ $# -ne 3 ]; then
  echo "Usage: $0 TICKET_KEY START_DATE END_DATE" >&2
  echo "Example: $0 VIS-454 2025-10-01 2025-11-01" >&2
  exit 1
fi

TICKET_KEY=$1
START_DATE=$2
END_DATE=$3

# Check if history is cached
if is_jira_history_cached "$TICKET_KEY"; then
  # Use cached history
  status_history=$(get_jira_status_history "$TICKET_KEY")
else
  # Ticket not cached or is open - need to fetch fresh
  if [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_BASE_URL:-}" ]; then
    # Can't fetch without credentials
    echo "0"
    exit 0
  fi
  
  # Fetch ticket with changelog
  AUTH_HEADER="Authorization: Basic $(echo -n "$JIRA_EMAIL:$JIRA_API_TOKEN" | base64)"
  
  changelog_response=$(curl -s -X GET \
    "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_KEY?expand=changelog&fields=status" \
    -H "Accept: application/json" \
    -H "$AUTH_HEADER" 2>/dev/null || echo '{}')
  
  if ! echo "$changelog_response" | jq -e '.changelog' > /dev/null 2>&1; then
    # No changelog available
    echo "0"
    exit 0
  fi
  
  # Extract status history from response
  status_history=$(echo "$changelog_response" | jq -c '[
    .changelog.histories[] | 
    select(.items[] | .field == "status") |
    {
      changed_at: .created,
      to_status: (.items[] | select(.field == "status") | .toString),
      from_status: (.items[] | select(.field == "status") | .fromString)
    }
  ]')
fi

# Check if ticket is currently in blocked status
current_status=""
if is_jira_cached "$TICKET_KEY"; then
  current_status=$(get_cached_jira_ticket "$TICKET_KEY" | jq -r '.status // ""')
elif [ -n "${JIRA_EMAIL:-}" ]; then
  AUTH_HEADER="Authorization: Basic $(echo -n "$JIRA_EMAIL:$JIRA_API_TOKEN" | base64)"
  current_status=$(curl -s -X GET \
    "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_KEY?fields=status" \
    -H "Accept: application/json" \
    -H "$AUTH_HEADER" 2>/dev/null | jq -r '.fields.status.name // ""')
fi

# Find last transition to blocked status
last_blocked_transition=$(echo "$status_history" | jq -r '
  [.[] | 
   select(.to_status | test("(?i)block|wait|hold|park")) | 
   .changed_at
  ] | sort | .[-1] // null
')

# Calculate blocked days if ticket is currently blocked
if echo "$current_status" | grep -qiE "block|wait|hold|park"; then
  if [ -n "$last_blocked_transition" ] && [ "$last_blocked_transition" != "null" ]; then
    blocked_start_date=$(echo "$last_blocked_transition" | cut -d'T' -f1)
    
    # Calculate overlap between blocked period and given date range
    # Blocked period: blocked_start_date → END_DATE
    # Given range: START_DATE → END_DATE
    # Overlap: max(blocked_start, START_DATE) → END_DATE
    
    if [ "$blocked_start_date" \< "$END_DATE" ]; then
      # Determine overlap start (later of blocked start or range start)
      if [ "$blocked_start_date" \> "$START_DATE" ]; then
        overlap_start="$blocked_start_date"
      else
        overlap_start="$START_DATE"
      fi
      
      # Calculate days between overlap_start and END_DATE
      blocked_days=$(echo "scale=0; ($(date -j -f "%Y-%m-%d" "$END_DATE" +%s) - $(date -j -f "%Y-%m-%d" "$overlap_start" +%s)) / 86400" | bc)
      
      if [ "$blocked_days" -gt 0 ]; then
        echo "$blocked_days"
      else
        echo "0"
      fi
    else
      echo "0"
    fi
  else
    echo "0"
  fi
else
  # Not currently blocked
  echo "0"
fi
