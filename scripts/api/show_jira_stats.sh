#!/bin/bash
# Show statistics about cached Jira tickets
# Usage: ./show_jira_stats.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JIRA_DB="$SCRIPT_DIR/../.cache/jira_tickets.db"

if [ ! -f "$JIRA_DB" ]; then
  echo "❌ Jira tickets database not found" >&2
  echo "Run: ./github-summary/scripts/database/jira_init.sh" >&2
  exit 1
fi

echo "📊 Jira Tickets Database Statistics"
echo "===================================="
echo ""

# Total tickets
total=$(sqlite3 "$JIRA_DB" "SELECT COUNT(*) FROM jira_tickets")
echo "Total tickets cached: $total"

if [ "$total" -eq 0 ]; then
  echo ""
  echo "No tickets cached yet."
  echo "Run: ./github-summary/scripts/api/fetch_all_github_tickets.sh"
  exit 0
fi

echo ""

# By status
echo "By Status:"
sqlite3 "$JIRA_DB" "
  SELECT status, COUNT(*) as count
  FROM jira_tickets
  GROUP BY status
  ORDER BY count DESC
" | while IFS='|' read -r status count; do
  echo "  $status: $count"
done

echo ""

# By issue type
echo "By Issue Type:"
sqlite3 "$JIRA_DB" "
  SELECT issue_type, COUNT(*) as count
  FROM jira_tickets
  GROUP BY issue_type
  ORDER BY count DESC
" | while IFS='|' read -r type count; do
  echo "  $type: $count"
done

echo ""

# Closed vs Open
closed=$(sqlite3 "$JIRA_DB" "SELECT COUNT(*) FROM jira_tickets WHERE is_closed = 1")
open=$(sqlite3 "$JIRA_DB" "SELECT COUNT(*) FROM jira_tickets WHERE is_closed = 0")
echo "Status:"
echo "  Closed: $closed"
echo "  Open: $open"

echo ""

# By chapter
echo "By Chapter:"
sqlite3 "$JIRA_DB" "
  SELECT 
    COALESCE(chapter, '(none)') as chapter, 
    COUNT(*) as count
  FROM jira_tickets
  GROUP BY chapter
  ORDER BY count DESC
" | while IFS='|' read -r chapter count; do
  echo "  $chapter: $count"
done

echo ""

# By service
echo "By Service:"
sqlite3 "$JIRA_DB" "
  SELECT 
    COALESCE(service, '(none)') as service, 
    COUNT(*) as count
  FROM jira_tickets
  GROUP BY service
  ORDER BY count DESC
" | while IFS='|' read -r service count; do
  echo "  $service: $count"
done

echo ""

# Story points
total_points=$(sqlite3 "$JIRA_DB" "SELECT COALESCE(SUM(story_points), 0) FROM jira_tickets WHERE story_points IS NOT NULL")
avg_points=$(sqlite3 "$JIRA_DB" "SELECT COALESCE(ROUND(AVG(story_points), 1), 0) FROM jira_tickets WHERE story_points IS NOT NULL")
echo "Story Points:"
echo "  Total: $total_points"
echo "  Average: $avg_points"

echo ""

# By CAPEX/OPEX
echo "By Work Type (CAPEX/OPEX):"
sqlite3 "$JIRA_DB" "
  SELECT 
    COALESCE(capex_opex, '(none)') as type, 
    COUNT(*) as count
  FROM jira_tickets
  GROUP BY capex_opex
  ORDER BY count DESC
" | while IFS='|' read -r type count; do
  echo "  $type: $count"
done

echo ""

# Unique epics
epic_count=$(sqlite3 "$JIRA_DB" "SELECT COUNT(DISTINCT epic_key) FROM jira_tickets WHERE epic_key IS NOT NULL AND epic_key != ''")
echo "Unique epics: $epic_count"

if [ "$epic_count" -gt 0 ]; then
  echo ""
  echo "Top Epics (by ticket count):"
  sqlite3 "$JIRA_DB" "
    SELECT 
      epic_key, 
      COALESCE(epic_title, epic_name, '') as title, 
      COUNT(*) as count
    FROM jira_tickets
    WHERE epic_key IS NOT NULL AND epic_key != ''
    GROUP BY epic_key, epic_title, epic_name
    ORDER BY count DESC
    LIMIT 10
  " | while IFS='|' read -r key title count; do
    if [ -n "$title" ]; then
      echo "  $key ($title): $count tickets"
    else
      echo "  $key: $count tickets"
    fi
  done
fi

echo ""
echo "Database location: $JIRA_DB"
