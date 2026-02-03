#!/usr/bin/env bats
# Tests for jira_helpers.sh

setup() {
  # Create temp directory for test database
  export TEST_CACHE_DIR=$(mktemp -d)
  export DB_PATH="$TEST_CACHE_DIR/jira_tickets.db"
  
  # Source the helpers (with mocked paths)
  export SCRIPT_DIR="$BATS_TEST_DIRNAME/../../github-summary/scripts/database"
  export CACHE_DIR="$TEST_CACHE_DIR"
  
  # Initialize test database (schema must match jira_init.sh)
  sqlite3 "$DB_PATH" <<'EOF'
CREATE TABLE jira_tickets (
  ticket_key TEXT PRIMARY KEY,
  summary TEXT,
  description TEXT,
  status TEXT,
  issue_type TEXT,
  assignee TEXT,
  assignee_id TEXT,
  reporter TEXT,
  reporter_id TEXT,
  priority TEXT,
  epic_key TEXT,
  epic_name TEXT,
  epic_title TEXT,
  parent_key TEXT,
  capex_opex TEXT,
  labels TEXT,
  resolution TEXT,
  story_points REAL,
  chapter TEXT,
  service TEXT,
  created_at TEXT,
  updated_at TEXT,
  resolved_at TEXT,
  fetched_at TEXT,
  is_closed INTEGER
);
CREATE INDEX idx_jira_epic ON jira_tickets(epic_key);
CREATE INDEX idx_jira_parent ON jira_tickets(parent_key);
EOF
  
  # Source helper functions
  source "$SCRIPT_DIR/jira_helpers.sh"
}

teardown() {
  rm -rf "$TEST_CACHE_DIR"
}

# === extract_description_text Tests ===

@test "extract_description_text: handles null description" {
  result=$(extract_description_text "null")
  [ "$result" = "" ]
}

@test "extract_description_text: handles empty description" {
  result=$(extract_description_text "")
  [ "$result" = "" ]
}

@test "extract_description_text: extracts simple text from ADF" {
  local adf='{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hello world"}]}]}'
  result=$(extract_description_text "$adf")
  [ "$result" = "Hello world" ]
}

@test "extract_description_text: extracts multiple paragraphs" {
  local adf='{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"First paragraph"}]},{"type":"paragraph","content":[{"type":"text","text":"Second paragraph"}]}]}'
  result=$(extract_description_text "$adf")
  [[ "$result" == *"First paragraph"* ]]
  [[ "$result" == *"Second paragraph"* ]]
}

@test "extract_description_text: handles nested content" {
  local adf='{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Start "},{"type":"text","text":"middle "},{"type":"text","text":"end"}]}]}'
  result=$(extract_description_text "$adf")
  [[ "$result" == *"Start"* ]]
  [[ "$result" == *"middle"* ]]
  [[ "$result" == *"end"* ]]
}

# === is_jira_cached Tests ===

@test "is_jira_cached: returns false for uncached ticket" {
  run is_jira_cached "VIS-999"
  [ "$status" -eq 1 ]
}

@test "is_jira_cached: returns true for closed cached ticket" {
  sqlite3 "$DB_PATH" <<EOF
INSERT INTO jira_tickets (ticket_key, summary, status, is_closed, fetched_at)
VALUES ('VIS-100', 'Test ticket', 'Done', 1, '2025-01-01T00:00:00Z');
EOF
  
  run is_jira_cached "VIS-100"
  [ "$status" -eq 0 ]
}

@test "is_jira_cached: returns false for open cached ticket" {
  sqlite3 "$DB_PATH" <<EOF
INSERT INTO jira_tickets (ticket_key, summary, status, is_closed, fetched_at)
VALUES ('VIS-101', 'Open ticket', 'In Progress', 0, '2025-01-01T00:00:00Z');
EOF
  
  run is_jira_cached "VIS-101"
  [ "$status" -eq 1 ]
}

# === cache_jira_ticket Tests ===

@test "cache_jira_ticket: caches basic ticket data" {
  local ticket_json='{
    "key": "VIS-200",
    "fields": {
      "summary": "Test summary",
      "description": {"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Test description"}]}]},
      "status": {"name": "Done"},
      "issuetype": {"name": "Task"},
      "assignee": {"accountId": "123", "displayName": "Test User"},
      "reporter": {"accountId": "456", "displayName": "Reporter User"},
      "priority": {"name": "High"},
      "resolution": {"name": "Done"},
      "labels": ["test", "example"],
      "created": "2025-01-01T00:00:00.000+0000",
      "updated": "2025-01-02T00:00:00.000+0000",
      "resolutiondate": "2025-01-02T00:00:00.000+0000"
    }
  }'
  
  cache_jira_ticket "$ticket_json"
  
  # Verify ticket was cached
  result=$(sqlite3 "$DB_PATH" "SELECT ticket_key, summary, status, is_closed FROM jira_tickets WHERE ticket_key='VIS-200'")
  [[ "$result" == *"VIS-200"* ]]
  [[ "$result" == *"Test summary"* ]]
  [[ "$result" == *"Done"* ]]
  [[ "$result" == *"1"* ]]  # is_closed should be 1
}

@test "cache_jira_ticket: handles epic field" {
  local ticket_json='{
    "key": "VIS-201",
    "fields": {
      "summary": "Epic child",
      "status": {"name": "Open"},
      "issuetype": {"name": "Story"},
      "customfield_10014": "VIS-500",
      "created": "2025-01-01T00:00:00.000+0000",
      "updated": "2025-01-01T00:00:00.000+0000"
    }
  }'
  
  cache_jira_ticket "$ticket_json"
  
  # Verify epic was captured
  result=$(sqlite3 "$DB_PATH" "SELECT epic_key FROM jira_tickets WHERE ticket_key='VIS-201'")
  [ "$result" = "VIS-500" ]
}

@test "cache_jira_ticket: handles parent field" {
  local ticket_json='{
    "key": "VIS-202",
    "fields": {
      "summary": "Subtask",
      "status": {"name": "Open"},
      "issuetype": {"name": "Sub-task"},
      "parent": {"key": "VIS-200"},
      "created": "2025-01-01T00:00:00.000+0000",
      "updated": "2025-01-01T00:00:00.000+0000"
    }
  }'
  
  cache_jira_ticket "$ticket_json"
  
  # Verify parent was captured
  result=$(sqlite3 "$DB_PATH" "SELECT parent_key FROM jira_tickets WHERE ticket_key='VIS-202'")
  [ "$result" = "VIS-200" ]
}

# === get_cached_jira_ticket Tests ===

@test "get_cached_jira_ticket: returns null for uncached ticket" {
  result=$(get_cached_jira_ticket "VIS-999")
  [ "$result" = "null" ]
}

@test "get_cached_jira_ticket: returns ticket data for cached ticket" {
  sqlite3 "$DB_PATH" <<EOF
INSERT INTO jira_tickets (ticket_key, summary, status, is_closed, fetched_at)
VALUES ('VIS-300', 'Cached ticket', 'Done', 1, '2025-01-01T00:00:00Z');
EOF
  
  result=$(get_cached_jira_ticket "VIS-300")
  [[ "$result" == *"VIS-300"* ]]
  [[ "$result" == *"Cached ticket"* ]]
}

# === get_tickets_by_epic Tests ===

@test "get_tickets_by_epic: returns empty array for epic with no tickets" {
  result=$(get_tickets_by_epic "VIS-999")
  [ "$result" = "[]" ]
}

@test "get_tickets_by_epic: returns tickets for epic" {
  sqlite3 "$DB_PATH" <<EOF
INSERT INTO jira_tickets (ticket_key, summary, epic_key, status, is_closed, fetched_at)
VALUES 
  ('VIS-401', 'Ticket 1', 'VIS-400', 'Done', 1, '2025-01-01T00:00:00Z'),
  ('VIS-402', 'Ticket 2', 'VIS-400', 'Done', 1, '2025-01-02T00:00:00Z'),
  ('VIS-403', 'Ticket 3', 'VIS-500', 'Done', 1, '2025-01-03T00:00:00Z');
EOF
  
  result=$(get_tickets_by_epic "VIS-400")
  [[ "$result" == *"VIS-401"* ]]
  [[ "$result" == *"VIS-402"* ]]
  [[ "$result" != *"VIS-403"* ]]  # Different epic
}

# === get_all_epic_keys Tests ===

@test "get_all_epic_keys: returns empty for no epics" {
  result=$(get_all_epic_keys)
  [ -z "$result" ]
}

@test "get_all_epic_keys: returns unique epic keys" {
  sqlite3 "$DB_PATH" <<EOF
INSERT INTO jira_tickets (ticket_key, summary, epic_key, status, is_closed, fetched_at)
VALUES 
  ('VIS-501', 'Ticket 1', 'VIS-500', 'Done', 1, '2025-01-01T00:00:00Z'),
  ('VIS-502', 'Ticket 2', 'VIS-500', 'Done', 1, '2025-01-02T00:00:00Z'),
  ('VIS-601', 'Ticket 3', 'VIS-600', 'Done', 1, '2025-01-03T00:00:00Z');
EOF
  
  result=$(get_all_epic_keys)
  [[ "$result" == *"VIS-500"* ]]
  [[ "$result" == *"VIS-600"* ]]
  
  # Count unique epics (should be 2)
  epic_count=$(echo "$result" | wc -l | tr -d ' ')
  [ "$epic_count" = "2" ]
}

# === JIRA Ticket Caching with TTL Tests ===

@test "closed ticket is cached forever" {
  # Setup: Create JIRA DB with closed ticket
  sqlite3 "$DB_PATH" <<EOF
INSERT INTO jira_tickets VALUES ('VIS-123', 'Test', 'Desc', 'Done', 'Story', 'user', 'id1', 'reporter', 'id2', 'High', NULL, NULL, NULL, NULL, NULL, NULL, 'Fixed', 3.0, NULL, NULL, '2025-08-01T10:00:00Z', '2025-08-10T12:00:00Z', '2025-08-10T12:00:00Z', datetime('now', '-30 days'), 1);
EOF
  
  # Should return true even though fetched 30 days ago
  run is_jira_cached_with_ttl "VIS-123" 24
  [ "$status" -eq 0 ]
}

@test "open ticket respects TTL" {
  sqlite3 "$DB_PATH" <<EOF
-- Ticket fetched 25 hours ago (outside 24hr TTL)
INSERT INTO jira_tickets VALUES ('VIS-456', 'Test', 'Desc', 'In Progress', 'Story', 'user', 'id1', 'reporter', 'id2', 'High', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 3.0, NULL, NULL, '2025-08-01T10:00:00Z', datetime('now', '-25 hours'), NULL, datetime('now', '-25 hours'), 0);
EOF
  
  # Should return false (needs refetch)
  run is_jira_cached_with_ttl "VIS-456" 24
  [ "$status" -ne 0 ]
}

@test "open ticket within TTL is cached" {
  sqlite3 "$DB_PATH" <<EOF
-- Ticket fetched 12 hours ago (within 24hr TTL)
INSERT INTO jira_tickets VALUES ('VIS-789', 'Test', 'Desc', 'In Progress', 'Story', 'user', 'id1', 'reporter', 'id2', 'High', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 3.0, NULL, NULL, '2025-08-01T10:00:00Z', datetime('now', '-12 hours'), NULL, datetime('now', '-12 hours'), 0);
EOF
  
  # Should return true (still fresh)
  run is_jira_cached_with_ttl "VIS-789" 24
  [ "$status" -eq 0 ]
}

# === JIRA History Caching Tests ===

@test "closed ticket history is cached forever" {
  # Create history table
  sqlite3 "$DB_PATH" <<EOF
CREATE TABLE jira_ticket_history (
  ticket_key TEXT,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT,
  author TEXT,
  fetched_at TEXT
);
INSERT INTO jira_tickets VALUES ('VIS-100', 'Test', 'Desc', 'Done', 'Story', 'user', 'id1', 'reporter', 'id2', 'High', NULL, NULL, NULL, NULL, NULL, NULL, 'Fixed', 3.0, NULL, NULL, '2025-08-01T10:00:00Z', '2025-08-10T12:00:00Z', '2025-08-10T12:00:00Z', datetime('now', '-30 days'), 1);
INSERT INTO jira_ticket_history VALUES ('VIS-100', 'status', 'To Do', 'Done', datetime('now', '-30 days'), 'user', datetime('now', '-30 days'));
EOF
  
  # Should return true (closed ticket history immutable)
  run is_jira_history_cached "VIS-100"
  [ "$status" -eq 0 ]
}

@test "open ticket history respects TTL" {
  sqlite3 "$DB_PATH" <<EOF
CREATE TABLE jira_ticket_history (
  ticket_key TEXT,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT,
  author TEXT,
  fetched_at TEXT
);
INSERT INTO jira_tickets VALUES ('VIS-200', 'Test', 'Desc', 'In Progress', 'Story', 'user', 'id1', 'reporter', 'id2', 'High', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 3.0, NULL, NULL, '2025-08-01T10:00:00Z', datetime('now', '-12 hours'), NULL, datetime('now', '-12 hours'), 0);
-- History fetched 25 hours ago (outside TTL)
INSERT INTO jira_ticket_history VALUES ('VIS-200', 'status', 'To Do', 'In Progress', datetime('now', '-25 hours'), 'user', datetime('now', '-25 hours'));
EOF
  
  # Should return false (needs refetch)
  run is_jira_history_cached "VIS-200"
  [ "$status" -ne 0 ]
}

@test "ticket without history returns false" {
  sqlite3 "$DB_PATH" <<EOF
CREATE TABLE jira_ticket_history (
  ticket_key TEXT,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT,
  author TEXT,
  fetched_at TEXT
);
-- Ticket exists but no history
INSERT INTO jira_tickets VALUES ('VIS-300', 'Test', 'Desc', 'In Progress', 'Story', 'user', 'id1', 'reporter', 'id2', 'High', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 3.0, NULL, NULL, '2025-08-01T10:00:00Z', datetime('now'), NULL, datetime('now'), 0);
EOF
  
  # Should return false (no history cached)
  run is_jira_history_cached "VIS-300"
  [ "$status" -ne 0 ]
}

@test "empty changelog is valid and cacheable" {
  sqlite3 "$DB_PATH" <<EOF
CREATE TABLE jira_ticket_history (
  ticket_key TEXT,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT,
  author TEXT,
  fetched_at TEXT
);
EOF
  
  # Empty changelog from API (ticket never transitioned)
  local empty_changelog='{"changelog": {"histories": []}}'
  
  run cache_jira_history "VIS-400" "$empty_changelog"
  [ "$status" -eq 0 ]
  
  # Should have 0 history entries, but history check should still work
  local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM jira_ticket_history WHERE ticket_key='VIS-400'")
  [ "$count" = "0" ]
}

# === JIRA Blocked Status Calculation Tests ===

@test "calculates blocked days from status transitions" {
  sqlite3 "$DB_PATH" <<EOF
CREATE TABLE jira_ticket_history (
  ticket_key TEXT,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT,
  author TEXT,
  fetched_at TEXT
);
-- Blocked for 3 days
INSERT INTO jira_ticket_history VALUES ('VIS-500', 'status', 'In Progress', 'Blocked', '2025-08-01T10:00:00Z', 'user', datetime('now'));
INSERT INTO jira_ticket_history VALUES ('VIS-500', 'status', 'Blocked', 'In Progress', '2025-08-04T10:00:00Z', 'user', datetime('now'));
EOF
  
  # Function is already sourced from jira_helpers.sh in setup
  local blocked_days=$(get_total_blocked_days "VIS-500" "2025-08-01" "2025-08-10")
  
  # Blocked from 08-01 10:00 to 08-04 10:00 = exactly 3 days
  [ "$blocked_days" = "3.0" ]
}

@test "handles ticket still blocked at end of timeline" {
  sqlite3 "$DB_PATH" <<EOF
CREATE TABLE jira_ticket_history (
  ticket_key TEXT,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT,
  author TEXT,
  fetched_at TEXT
);
-- Entered blocked state, never exited
INSERT INTO jira_ticket_history VALUES ('VIS-600', 'status', 'In Progress', 'Blocked', '2025-08-05T10:00:00Z', 'user', datetime('now'));
EOF
  
  # Function is already sourced from jira_helpers.sh in setup
  # Timeline ends on 2025-08-10, ticket blocked since 08-05 10:00
  local blocked_days=$(get_total_blocked_days "VIS-600" "2025-08-01" "2025-08-10")
  
  # Blocked from 08-05 10:00 to 08-10 00:00 = 4 days 14 hours = 4.6 days
  [ "$blocked_days" = "4.6" ]
}
