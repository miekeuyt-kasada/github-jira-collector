#!/usr/bin/env bats
# Tests for 00b_refresh_jira_cache.sh

load '../test_helper'

SCRIPT="$STEPS_DIR/00b_refresh_jira_cache.sh"

setup() {
  TEST_TMPDIR=$(mktemp -d "$BATS_TMPDIR/jira-cache-test.XXXXXX")
  
  MOCK_PROJECT="$TEST_TMPDIR/mock-project"
  mkdir -p "$MOCK_PROJECT/steps"
  mkdir -p "$MOCK_PROJECT/github-summary/scripts/.cache"
  mkdir -p "$MOCK_PROJECT/github-summary/scripts/api"
  
  # Copy script under test
  cp "$STEPS_DIR/00b_refresh_jira_cache.sh" "$MOCK_PROJECT/steps/"
  
  # Mock get_jira_ticket.sh
  cat > "$MOCK_PROJECT/github-summary/scripts/api/get_jira_ticket.sh" <<'EOF'
#!/bin/bash
echo "Mock JIRA fetch: $*" >&2
EOF
  chmod +x "$MOCK_PROJECT/github-summary/scripts/api/get_jira_ticket.sh"
  
  MOCK_DB="$MOCK_PROJECT/github-summary/scripts/.cache/github_data.db"
  
  export JIRA_EMAIL="test@example.com"
  export JIRA_API_TOKEN="fake_token"
  export JIRA_BASE_URL="https://example.atlassian.net"
}

teardown() {
  unset JIRA_EMAIL
  unset JIRA_API_TOKEN
  unset JIRA_BASE_URL
  rm -rf "$TEST_TMPDIR"
}

@test "script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "skips when JIRA credentials not set" {
  unset JIRA_EMAIL
  
  cd "$MOCK_PROJECT"
  run ./steps/00b_refresh_jira_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "Skipping JIRA cache refresh"
  assert_contains "$output" "credentials not set"
}

@test "fails when GitHub cache missing" {
  # No DB file
  cd "$MOCK_PROJECT"
  run ./steps/00b_refresh_jira_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -ne 0 ]
  assert_contains "$output" "GitHub cache not found"
}

@test "skips when no tickets in date range" {
  # Create DB with no JIRA tickets
  sqlite3 "$MOCK_DB" <<EOF
CREATE TABLE prs (repo TEXT, pr_number INT, jira_ticket TEXT, created_at TEXT);
INSERT INTO prs VALUES ('test/repo', 100, NULL, '2025-07-01T10:00:00Z');
EOF
  
  cd "$MOCK_PROJECT"
  run ./steps/00b_refresh_jira_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "No JIRA tickets found"
}

@test "fetches tickets when found in cache" {
  # Create DB with JIRA tickets
  sqlite3 "$MOCK_DB" <<EOF
CREATE TABLE prs (repo TEXT, pr_number INT, jira_ticket TEXT, created_at TEXT);
INSERT INTO prs VALUES ('test/repo', 100, 'VIS-123', '2025-07-01T10:00:00Z');
INSERT INTO prs VALUES ('test/repo', 101, 'VIS-456', '2025-07-15T10:00:00Z');
EOF
  
  cd "$MOCK_PROJECT"
  run ./steps/00b_refresh_jira_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "Found 2 unique ticket(s)"
  assert_contains "$output" "VIS-123"
  assert_contains "$output" "VIS-456"
  assert_contains "$output" "JIRA cache refreshed"
}

@test "queries correct date range" {
  # Create DB with tickets in and out of range
  sqlite3 "$MOCK_DB" <<EOF
CREATE TABLE prs (repo TEXT, pr_number INT, jira_ticket TEXT, created_at TEXT);
INSERT INTO prs VALUES ('test/repo', 100, 'VIS-123', '2025-07-01T10:00:00Z');
INSERT INTO prs VALUES ('test/repo', 101, 'VIS-OLD', '2025-06-01T10:00:00Z');
INSERT INTO prs VALUES ('test/repo', 102, 'VIS-FUTURE', '2025-08-01T10:00:00Z');
EOF
  
  cd "$MOCK_PROJECT"
  run ./steps/00b_refresh_jira_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "Found 1 unique ticket(s)"
  assert_contains "$output" "VIS-123"
  # Should NOT contain tickets outside range
  [[ "$output" != *"VIS-OLD"* ]]
  [[ "$output" != *"VIS-FUTURE"* ]]
}

@test "deduplicates ticket keys" {
  # Multiple PRs with same ticket
  sqlite3 "$MOCK_DB" <<EOF
CREATE TABLE prs (repo TEXT, pr_number INT, jira_ticket TEXT, created_at TEXT);
INSERT INTO prs VALUES ('test/repo', 100, 'VIS-123', '2025-07-01T10:00:00Z');
INSERT INTO prs VALUES ('test/repo', 101, 'VIS-123', '2025-07-15T10:00:00Z');
INSERT INTO prs VALUES ('test/repo', 102, 'VIS-456', '2025-07-20T10:00:00Z');
EOF
  
  cd "$MOCK_PROJECT"
  run ./steps/00b_refresh_jira_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  # Should report 2 unique tickets, not 3
  assert_contains "$output" "Found 2 unique ticket(s)"
}

@test "fails with wrong number of arguments" {
  cd "$MOCK_PROJECT"
  run ./steps/00b_refresh_jira_cache.sh "2025-07"
  [ "$status" -ne 0 ]
}
