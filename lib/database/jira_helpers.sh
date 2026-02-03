#!/bin/bash
# Database helper functions for Jira ticket caching

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CACHE_DIR="${CACHE_DIR:-$SCRIPT_DIR/../.cache}"
DB_PATH="${DB_PATH:-$CACHE_DIR/jira_tickets.db}"

# Extract plain text from Atlassian Document Format (rich text)
extract_description_text() {
  local description_json="$1"
  
  # If description is null or empty, return empty string
  if [ "$description_json" = "null" ] || [ -z "$description_json" ]; then
    echo ""
    return
  fi
  
  # Extract all text nodes from the content array
  # ADF structure: { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "..." }] }] }
  echo "$description_json" | jq -r '
    .. | 
    objects | 
    select(.type == "text") | 
    .text
  ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

# Check if a ticket is cached and closed (immutable)
is_jira_cached() {
  local ticket_key=$1
  
  result=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM jira_tickets WHERE ticket_key='$ticket_key' AND is_closed=1" 2>/dev/null)
  [ "$result" = "1" ]
}

# Check if a ticket is cached (regardless of status) and check TTL
is_jira_cached_with_ttl() {
  local ticket_key=$1
  local ttl_hours=${2:-24}  # Default 24 hour TTL
  
  # Check if ticket exists and is either closed or within TTL
  result=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM jira_tickets 
    WHERE ticket_key='$ticket_key' 
    AND (
      is_closed=1 
      OR datetime(fetched_at) >= datetime('now', '-$ttl_hours hours')
    )
  " 2>/dev/null)
  [ "$result" = "1" ]
}

# Cache Jira ticket metadata
cache_jira_ticket() {
  local ticket_json=$1
  
  # Extract fields from JSON
  local ticket_key=$(echo "$ticket_json" | jq -r '.key')
  local summary=$(echo "$ticket_json" | jq -r '.fields.summary // ""' | sed "s/'/''/g")
  local description_raw=$(echo "$ticket_json" | jq -c '.fields.description // null')
  local description=$(extract_description_text "$description_raw" | sed "s/'/''/g")
  
  local status=$(echo "$ticket_json" | jq -r '.fields.status.name // ""' | sed "s/'/''/g")
  local issue_type=$(echo "$ticket_json" | jq -r '.fields.issuetype.name // ""' | sed "s/'/''/g")
  
  local assignee=$(echo "$ticket_json" | jq -r '.fields.assignee.displayName // ""' | sed "s/'/''/g")
  local assignee_id=$(echo "$ticket_json" | jq -r '.fields.assignee.accountId // ""')
  
  local reporter=$(echo "$ticket_json" | jq -r '.fields.reporter.displayName // ""' | sed "s/'/''/g")
  local reporter_id=$(echo "$ticket_json" | jq -r '.fields.reporter.accountId // ""')
  
  local priority=$(echo "$ticket_json" | jq -r '.fields.priority.name // ""' | sed "s/'/''/g")
  local resolution=$(echo "$ticket_json" | jq -r '.fields.resolution.name // ""' | sed "s/'/''/g")
  
  local parent_key=$(echo "$ticket_json" | jq -r '.fields.parent.key // ""')
  
  # Epic field - use environment variable or try common field names
  local epic_key=""
  local epic_name=""
  local epic_title=""
  
  # Epic Link (e.g., "VIS-98")
  local epic_fields="${JIRA_EPIC_FIELD:-customfield_10009} customfield_10009 customfield_10014 customfield_10008 customfield_10100"
  
  for field in $epic_fields; do
    epic_key=$(echo "$ticket_json" | jq -r ".fields.$field // \"\"")
    if [ -n "$epic_key" ] && [ "$epic_key" != "null" ]; then
      break
    fi
  done
  
  # If epic_key is an object (newer Jira format), extract the key
  if echo "$epic_key" | jq -e 'type == "object"' > /dev/null 2>&1; then
    epic_name=$(echo "$epic_key" | jq -r '.name // ""')
    epic_key=$(echo "$epic_key" | jq -r '.key // ""')
  fi
  
  # Epic Name/Title (e.g., "Threat Sessions MVP")
  epic_title=$(echo "$ticket_json" | jq -r "
    .fields.${JIRA_EPIC_NAME_FIELD:-customfield_10008} // 
    .fields.customfield_10008 // \"\"
  " | sed "s/'/''/g")
  
  local labels=$(echo "$ticket_json" | jq -c '.fields.labels // []')
  
  # Story points
  local story_points=$(echo "$ticket_json" | jq -r "
    .fields.${JIRA_STORY_POINTS_FIELD:-customfield_11004} // 
    .fields.customfield_11004 // 
    .fields.customfield_10016 // \"\"
  ")
  
  # Chapter (team/area) - merge from multiple possible fields
  # Handle both single objects and arrays of objects
  local chapter_primary=$(echo "$ticket_json" | jq -r "
    (.fields.${JIRA_CHAPTER_FIELD:-customfield_11782} // 
     .fields.customfield_11782 // null) | 
    if type == \"array\" then 
      [.[] | select(.value != \"Template Only\") | .value] | join(\" / \")
    elif type == \"object\" then 
      if .value == \"Template Only\" then \"\" else .value end
    else 
      . 
    end // \"\"
  ")
  local chapter_alt=$(echo "$ticket_json" | jq -r "
    (.fields.${JIRA_CHAPTER_ALT_FIELD:-customfield_12384} // 
     .fields.customfield_12384 // null) | 
    if type == \"array\" then 
      [.[] | select(.value != \"Template Only\") | .value] | join(\" / \")
    elif type == \"object\" then 
      if .value == \"Template Only\" then \"\" else .value end
    else 
      . 
    end // \"\"
  ")
  
  # Merge chapter fields intelligently
  local chapter=""
  if [ -n "$chapter_primary" ] && [ "$chapter_primary" != "null" ]; then
    chapter="$chapter_primary"
    # If alt is different and non-empty, append it
    if [ -n "$chapter_alt" ] && [ "$chapter_alt" != "null" ] && [ "$chapter_alt" != "$chapter_primary" ]; then
      chapter="$chapter / $chapter_alt"
    fi
  elif [ -n "$chapter_alt" ] && [ "$chapter_alt" != "null" ]; then
    chapter="$chapter_alt"
  fi
  chapter=$(echo "$chapter" | sed "s/'/''/g")
  
  # Service (product/service) - merge from multiple possible fields
  # Handle both single objects and arrays of objects
  local service_primary=$(echo "$ticket_json" | jq -r "
    (.fields.${JIRA_SERVICE_FIELD:-customfield_11783} // 
     .fields.customfield_11783 // null) | 
    if type == \"array\" then 
      [.[] | select(.value != \"Template Only\") | .value] | join(\" / \")
    elif type == \"object\" then 
      if .value == \"Template Only\" then \"\" else .value end
    else 
      . 
    end // \"\"
  ")
  local service_alt=$(echo "$ticket_json" | jq -r "
    (.fields.${JIRA_SERVICE_ALT_FIELD:-customfield_12383} // 
     .fields.customfield_12383 // null) | 
    if type == \"array\" then 
      [.[] | select(.value != \"Template Only\") | .value] | join(\" / \")
    elif type == \"object\" then 
      if .value == \"Template Only\" then \"\" else .value end
    else 
      . 
    end // \"\"
  ")
  
  # Merge service fields intelligently
  local service=""
  if [ -n "$service_primary" ] && [ "$service_primary" != "null" ]; then
    service="$service_primary"
    # If alt is different and non-empty, append it
    if [ -n "$service_alt" ] && [ "$service_alt" != "null" ] && [ "$service_alt" != "$service_primary" ]; then
      service="$service / $service_alt"
    fi
  elif [ -n "$service_alt" ] && [ "$service_alt" != "null" ]; then
    service="$service_alt"
  fi
  service=$(echo "$service" | sed "s/'/''/g")
  
  # CAPEX vs OPEX
  local capex_opex=$(echo "$ticket_json" | jq -r "
    (.fields.${JIRA_CAPEX_OPEX_FIELD:-customfield_11280} // 
     .fields.customfield_11280 // null) | 
    if type == \"object\" then .value else . end // \"\"
  " | sed "s/'/''/g")
  
  local created_at=$(echo "$ticket_json" | jq -r '.fields.created // ""')
  local updated_at=$(echo "$ticket_json" | jq -r '.fields.updated // ""')
  local resolved_at=$(echo "$ticket_json" | jq -r '.fields.resolutiondate // ""')
  
  local fetched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Determine if ticket is closed
  local is_closed=0
  if [[ "$status" =~ ^(Done|Closed|Resolved|Complete)$ ]]; then
    is_closed=1
  fi
  
  # Convert empty strings to NULL for SQL
  [ -z "$assignee" ] && assignee="NULL" || assignee="'$assignee'"
  [ -z "$assignee_id" ] && assignee_id="NULL" || assignee_id="'$assignee_id'"
  [ -z "$reporter" ] && reporter="NULL" || reporter="'$reporter'"
  [ -z "$reporter_id" ] && reporter_id="NULL" || reporter_id="'$reporter_id'"
  [ -z "$priority" ] && priority="NULL" || priority="'$priority'"
  [ -z "$resolution" ] && resolution="NULL" || resolution="'$resolution'"
  [ -z "$parent_key" ] && parent_key="NULL" || parent_key="'$parent_key'"
  [ -z "$epic_key" ] && epic_key="NULL" || epic_key="'$epic_key'"
  [ -z "$epic_name" ] && epic_name="NULL" || epic_name="'$epic_name'"
  [ -z "$epic_title" ] && epic_title="NULL" || epic_title="'$epic_title'"
  [ -z "$capex_opex" ] && capex_opex="NULL" || capex_opex="'$capex_opex'"
  [ -z "$story_points" ] || [ "$story_points" = "null" ] && story_points="NULL"
  [ -z "$chapter" ] && chapter="NULL" || chapter="'$chapter'"
  [ -z "$service" ] && service="NULL" || service="'$service'"
  [ -z "$resolved_at" ] || [ "$resolved_at" = "null" ] && resolved_at="NULL" || resolved_at="'$resolved_at'"
  
  # Insert or replace
  sqlite3 "$DB_PATH" <<EOF
INSERT OR REPLACE INTO jira_tickets (
  ticket_key, summary, description, status, issue_type,
  assignee, assignee_id, reporter, reporter_id, priority,
  epic_key, epic_name, epic_title, parent_key, capex_opex, labels, resolution,
  story_points, chapter, service,
  created_at, updated_at, resolved_at, fetched_at, is_closed
) VALUES (
  '$ticket_key', '$summary', '$description', '$status', '$issue_type',
  $assignee, $assignee_id, $reporter, $reporter_id, $priority,
  $epic_key, $epic_name, $epic_title, $parent_key, $capex_opex, '$labels', $resolution,
  $story_points, $chapter, $service,
  '$created_at', '$updated_at', $resolved_at, '$fetched_at', $is_closed
);
EOF
}

# Get cached ticket with all metadata
get_cached_jira_ticket() {
  local ticket_key=$1
  
  local result=$(sqlite3 "$DB_PATH" -json "SELECT * FROM jira_tickets WHERE ticket_key='$ticket_key'" 2>/dev/null)
  if [ -z "$result" ]; then
    echo "null"
  else
    echo "$result" | jq '.[0] // null'
  fi
}

# Get all tickets for a specific epic
get_tickets_by_epic() {
  local epic_key=$1
  
  local result=$(sqlite3 "$DB_PATH" -json "SELECT * FROM jira_tickets WHERE epic_key='$epic_key' ORDER BY created_at" 2>/dev/null)
  if [ -z "$result" ]; then
    echo "[]"
  else
    echo "$result"
  fi
}

# Get all tickets with a specific label
get_tickets_by_label() {
  local label=$1
  
  # JSON array search - check if label is in the labels array
  sqlite3 "$DB_PATH" -json "SELECT * FROM jira_tickets WHERE labels LIKE '%\"$label\"%' ORDER BY created_at" 2>/dev/null
}

# Get all unique epic keys from cached tickets
get_all_epic_keys() {
  sqlite3 "$DB_PATH" "SELECT DISTINCT epic_key FROM jira_tickets WHERE epic_key IS NOT NULL AND epic_key != '' ORDER BY epic_key" 2>/dev/null
}

# ============================================================================
# JIRA History Functions (for caching ticket changelog)
# ============================================================================

# Check if ticket history is cached
is_jira_history_cached() {
  local ticket_key=$1
  
  # Check if history exists in cache
  local history_count=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM jira_ticket_history 
    WHERE ticket_key='$ticket_key'
  " 2>/dev/null)
  
  if [ "$history_count" -gt 0 ]; then
    # History exists, check if ticket is closed (immutable) or within TTL
    local is_closed=$(sqlite3 "$DB_PATH" "
      SELECT is_closed FROM jira_tickets 
      WHERE ticket_key='$ticket_key'
    " 2>/dev/null)
    
    if [ "$is_closed" = "1" ]; then
      # Closed ticket: history is immutable, use cache
      return 0
    else
      # Open ticket: check if history was fetched recently (24hr TTL)
      local fetched_recently=$(sqlite3 "$DB_PATH" "
        SELECT COUNT(*) FROM jira_ticket_history
        WHERE ticket_key='$ticket_key'
        AND datetime(fetched_at) >= datetime('now', '-24 hours')
        LIMIT 1
      " 2>/dev/null)
      [ "$fetched_recently" -gt 0 ]
    fi
  else
    # No history cached
    return 1
  fi
}

# Cache JIRA changelog entries from API response
cache_jira_history() {
  local ticket_key=$1
  local changelog_json=$2
  
  # Parse changelog and insert each history entry
  # Use NULL placeholder for empty strings to handle tab parsing correctly
  echo "$changelog_json" | jq -r '.changelog.histories[]? | 
    .created as $ts | 
    (.author.displayName // .author.emailAddress // "unknown") as $author |
    .items[]? | 
    [
      .field, 
      ((.fromString // "") | if . == "" then "NULL" else . end), 
      ((.toString // "") | if . == "" then "NULL" else . end), 
      $ts, 
      $author
    ] | 
    @tsv
  ' | while IFS=$'\t' read -r field old_val new_val ts author; do
    # Convert NULL placeholder back to empty string
    [ "$old_val" = "NULL" ] && old_val=""
    [ "$new_val" = "NULL" ] && new_val=""
    
    # Escape single quotes for SQL
    old_val=$(echo "$old_val" | sed "s/'/''/g")
    new_val=$(echo "$new_val" | sed "s/'/''/g")
    author=$(echo "$author" | sed "s/'/''/g")
    field=$(echo "$field" | sed "s/'/''/g")
    
    # Insert, skip if duplicate
    sqlite3 "$DB_PATH" "
      INSERT OR IGNORE INTO jira_ticket_history 
        (ticket_key, field_name, old_value, new_value, changed_at, changed_by)
      VALUES 
        ('$ticket_key', '$field', '$old_val', '$new_val', '$ts', '$author')
    " 2>/dev/null
  done
}

# Get all status transitions for a ticket (ordered by date)
get_jira_status_history() {
  local ticket_key=$1
  
  sqlite3 "$DB_PATH" -json "
    SELECT 
      changed_at,
      old_value as from_status,
      new_value as to_status,
      changed_by
    FROM jira_ticket_history
    WHERE ticket_key='$ticket_key' 
      AND field_name='status'
    ORDER BY changed_at
  " 2>/dev/null
}

# Get blocked periods for a ticket (when status contained block/wait/hold/park keywords)
get_jira_blocked_periods() {
  local ticket_key=$1
  
  sqlite3 "$DB_PATH" -json "
    SELECT 
      changed_at as transition_date,
      new_value as status,
      changed_by
    FROM jira_ticket_history
    WHERE ticket_key='$ticket_key' 
      AND field_name='status'
      AND (
        LOWER(new_value) LIKE '%block%' 
        OR LOWER(new_value) LIKE '%wait%'
        OR LOWER(new_value) LIKE '%hold%'
        OR LOWER(new_value) LIKE '%park%'
      )
    ORDER BY changed_at
  " 2>/dev/null
}

# Get all history for a ticket (all fields)
get_jira_full_history() {
  local ticket_key=$1
  
  sqlite3 "$DB_PATH" -json "
    SELECT 
      field_name,
      old_value,
      new_value,
      changed_at,
      changed_by
    FROM jira_ticket_history
    WHERE ticket_key='$ticket_key'
    ORDER BY changed_at
  " 2>/dev/null
}

# Calculate total days a ticket was blocked during a date range
# Extracted from get_jira_blocked_time.sh for testability
get_total_blocked_days() {
  local ticket_key="$1"
  local start_date="$2"
  local end_date="$3"
  
  # Get status history transitions for this ticket
  local history=$(sqlite3 "$DB_PATH" <<EOF
SELECT changed_at, old_value, new_value
FROM jira_ticket_history
WHERE ticket_key = '$ticket_key'
  AND field = 'status'
ORDER BY changed_at ASC;
EOF
  )
  
  if [ -z "$history" ]; then
    echo "0.0"
    return
  fi
  
  # Convert dates to epoch for calculation (UTC)
  local start_epoch end_epoch
  if date -u -j -f "%Y-%m-%d" "${start_date}T00:00:00Z" "+%s" >/dev/null 2>&1; then
    # macOS - use UTC
    start_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${start_date}T00:00:00Z" "+%s")
    end_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${end_date}T00:00:00Z" "+%s")
  else
    # Linux - use UTC
    start_epoch=$(date -u -d "${start_date}T00:00:00Z" "+%s")
    end_epoch=$(date -u -d "${end_date}T00:00:00Z" "+%s")
  fi
  
  local total_blocked_seconds=0
  local currently_blocked=0
  local blocked_since_epoch=0
  
  # Parse each status transition
  while IFS='|' read -r changed_at old_value new_value; do
    [ -z "$changed_at" ] && continue
    
    local change_epoch
    if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$changed_at" "+%s" >/dev/null 2>&1; then
      change_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$changed_at" "+%s")
    else
      change_epoch=$(date -u -d "$changed_at" "+%s")
    fi
    
    # Skip if outside date range
    [ "$change_epoch" -lt "$start_epoch" ] && continue
    [ "$change_epoch" -gt "$end_epoch" ] && break
    
    # Check if entering blocked state
    if [[ "$new_value" =~ Blocked ]] || [[ "$new_value" =~ Waiting ]]; then
      currently_blocked=1
      blocked_since_epoch=$change_epoch
    # Check if exiting blocked state
    elif [ "$currently_blocked" -eq 1 ]; then
      # If not blocked anymore, calculate duration
      if [[ ! "$new_value" =~ Blocked ]] && [[ ! "$new_value" =~ Waiting ]]; then
        local blocked_duration=$((change_epoch - blocked_since_epoch))
        total_blocked_seconds=$((total_blocked_seconds + blocked_duration))
        currently_blocked=0
      fi
    fi
  done <<< "$history"
  
  # If still blocked at end, count remaining time
  if [ "$currently_blocked" -eq 1 ]; then
    local remaining=$((end_epoch - blocked_since_epoch))
    total_blocked_seconds=$((total_blocked_seconds + remaining))
  fi
  
  # Convert to days with one decimal
  if command -v awk >/dev/null 2>&1; then
    local days_float=$(awk "BEGIN {printf \"%.1f\", $total_blocked_seconds / 86400}")
    echo "$days_float"
  else
    # Fallback to bash arithmetic (integer division)
    local days_int=$((total_blocked_seconds / 86400))
    echo "${days_int}.0"
  fi
}
