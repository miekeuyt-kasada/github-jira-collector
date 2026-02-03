#!/bin/bash
# Fetch JIRA ticket data referenced in GitHub PRs and cache to SQLite database
# Usage: ./get_jira_data.sh [--force] [--limit N]
# Examples:
#   ./get_jira_data.sh                    # Fetch all JIRA tickets from GitHub PRs
#   ./get_jira_data.sh --force            # Force refresh all tickets (ignore cache)
#   ./get_jira_data.sh --limit 10         # Test with first 10 tickets only

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Load environment variables from .env.local if it exists
if [ -f "$SCRIPT_DIR/../.env.local" ]; then
  source "$SCRIPT_DIR/../.env.local"
fi

# Check required environment variables
if [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_BASE_URL:-}" ]; then
  echo "❌ Error: Required JIRA environment variables not set" >&2
  echo "" >&2
  echo "Please add to .env.local:" >&2
  echo "  JIRA_EMAIL=your-email@domain.com" >&2
  echo "  JIRA_API_TOKEN=your-api-token" >&2
  echo "  JIRA_BASE_URL=https://your-org.atlassian.net" >&2
  echo "" >&2
  echo "Get API token: https://id.atlassian.com/manage-profile/security/api-tokens" >&2
  exit 1
fi

# Parse flags
FORCE_REFRESH=false
LIMIT=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force)
      FORCE_REFRESH=true
      shift
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--force] [--limit N]" >&2
      exit 1
      ;;
  esac
done

# Initialize JIRA database
"$SCRIPT_DIR/database/jira_init.sh"

# Check GitHub database exists
GITHUB_DB="$SCRIPT_DIR/.cache/github_data.db"
if [ ! -f "$GITHUB_DB" ]; then
  echo "❌ Error: GitHub database not found at $GITHUB_DB" >&2
  echo "   Run ./get_github_data.sh first to fetch GitHub data" >&2
  exit 1
fi

# Get unique JIRA tickets from GitHub PRs
echo "📊 Extracting JIRA tickets from GitHub PRs..."
JIRA_TICKETS=$(sqlite3 "$GITHUB_DB" "
  SELECT DISTINCT jira_ticket 
  FROM prs 
  WHERE jira_ticket IS NOT NULL 
    AND jira_ticket != '' 
  ORDER BY jira_ticket
" 2>/dev/null || echo "")

if [ -z "$JIRA_TICKETS" ]; then
  echo "ℹ️  No JIRA tickets found in GitHub PRs"
  echo "   GitHub PRs may not have JIRA ticket references yet"
  exit 0
fi

TICKET_COUNT=$(echo "$JIRA_TICKETS" | wc -l | tr -d ' ')
echo "   Found $TICKET_COUNT unique JIRA tickets"

# Apply limit if specified
if [ "$LIMIT" -gt 0 ]; then
  echo "⚠️  Test mode: limiting to first $LIMIT tickets"
  JIRA_TICKETS=$(echo "$JIRA_TICKETS" | head -n "$LIMIT")
  TICKET_COUNT=$LIMIT
fi

# Clear cache if force refresh
if [ "$FORCE_REFRESH" = true ]; then
  echo "🔄 Force refresh: clearing JIRA cache..."
  JIRA_DB="$SCRIPT_DIR/.cache/jira_tickets.db"
  sqlite3 "$JIRA_DB" "DELETE FROM jira_tickets;" 2>/dev/null || true
  sqlite3 "$JIRA_DB" "DELETE FROM jira_ticket_history;" 2>/dev/null || true
fi

# Fetch each ticket
echo "🔍 Fetching JIRA tickets..."
echo ""

FETCHED=0
CACHED=0
FAILED=0
FIRST_ERROR=""

for ticket in $JIRA_TICKETS; do
  [ -z "$ticket" ] && continue
  
  # Use get_jira_ticket.sh which handles caching
  # Capture stderr to show first error for debugging
  if OUTPUT=$("$SCRIPT_DIR/api/get_jira_ticket.sh" "$ticket" 2>&1 >/dev/null); then
    FETCHED=$((FETCHED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "  ✗ Failed: $ticket"
    
    # Save first error for diagnosis
    if [ -z "$FIRST_ERROR" ] && [ -n "$OUTPUT" ]; then
      FIRST_ERROR="$OUTPUT"
    fi
  fi
done

# Show diagnostic info if all tickets failed
if [ "$FAILED" -gt 0 ] && [ "$FETCHED" -eq 0 ]; then
  echo ""
  echo "❌ All tickets failed to fetch. Diagnostic info:"
  echo ""
  echo "First error:"
  echo "$FIRST_ERROR" | head -10
  echo ""
  echo "Check:"
  echo "  • JIRA credentials in .env.local (JIRA_EMAIL, JIRA_API_TOKEN, JIRA_BASE_URL)"
  echo "  • API token is valid: https://id.atlassian.com/manage-profile/security/api-tokens"
  echo "  • You have access to these tickets in JIRA"
fi

echo ""
echo "✅ JIRA data cached to database"
echo "   Total tickets: $TICKET_COUNT"
echo ""
echo "Next steps:"
echo "  • View JIRA stats: ./lib/api/show_jira_stats.sh"
echo "  • Query data: ./lib/database/query_jira_data.sh"
