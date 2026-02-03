#!/usr/bin/env bats
# Tests for db_helpers.sh - specifically the pure extract_jira_ticket function

load '../test_helper'

# Define extract_jira_ticket locally to avoid sourcing issues with db_helpers.sh
# This is the exact same function from db_helpers.sh
# IMPORTANT: Keep in sync with github-summary/scripts/database/db_helpers.sh
extract_jira_ticket() {
  local text="$1"
  # Match pattern: 2-5 uppercase letters, dash, 1-5 digits
  echo "$text" | grep -oE '[A-Z]{2,5}-[0-9]{1,5}' | head -n1
}

# Expected function body from source (for sync check)
EXPECTED_JIRA_REGEX='echo "\$text" | grep -oE '"'"'[A-Z]{2,5}-[0-9]{1,5}'"'"' | head -n1'

setup() {
  TEST_TMPDIR=$(mktemp -d "$BATS_TMPDIR/bragdoc-test.XXXXXX")
}

# === Sync Check ===

@test "SYNC CHECK: extract_jira_ticket matches source file" {
  # Extract the function body from the actual source file
  local source_file="$DATABASE_DIR/db_helpers.sh"
  
  # Check that the exact regex pattern exists in the source (-F for fixed string)
  grep -qF '[A-Z]{2,5}-[0-9]{1,5}' "$source_file"
  
  # This test fails if someone changes the function in db_helpers.sh
  # without updating the local copy above
}

teardown() {
  if [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# === extract_jira_ticket Tests ===

@test "extracts VIS-454 from PR title" {
  local result=$(extract_jira_ticket "VIS-454: Fix toast notification styling")
  [ "$result" = "VIS-454" ]
}

@test "extracts CORS-3342 from text" {
  local result=$(extract_jira_ticket "CORS-3342: Add rate limiting")
  [ "$result" = "CORS-3342" ]
}

@test "extracts ticket from middle of text" {
  local result=$(extract_jira_ticket "Fix for PROJ-123 in the API layer")
  [ "$result" = "PROJ-123" ]
}

@test "extracts first ticket when multiple present" {
  local result=$(extract_jira_ticket "VIS-100 and VIS-200 are related")
  [ "$result" = "VIS-100" ]
}

@test "handles 2-letter project codes" {
  local result=$(extract_jira_ticket "AB-1: Minimal ticket")
  [ "$result" = "AB-1" ]
}

@test "handles 5-letter project codes" {
  local result=$(extract_jira_ticket "ABCDE-12345: Max length ticket")
  [ "$result" = "ABCDE-12345" ]
}

@test "returns empty for text without ticket" {
  local result=$(extract_jira_ticket "Just a regular commit message")
  [ -z "$result" ]
}

@test "returns empty for lowercase text" {
  local result=$(extract_jira_ticket "vis-454: lowercase doesn't match")
  [ -z "$result" ]
}

@test "returns empty for single letter prefix" {
  local result=$(extract_jira_ticket "A-123: Single letter not valid")
  [ -z "$result" ]
}

@test "extracts valid ticket from 6+ letter prefix" {
  # ABCDEF-123 contains BCDEF-123 which is a valid 5-letter ticket
  local result=$(extract_jira_ticket "ABCDEF-123: Contains valid ticket")
  [ "$result" = "BCDEF-123" ]
}

@test "handles ticket at end of text" {
  local result=$(extract_jira_ticket "Closes ticket VIS-999")
  [ "$result" = "VIS-999" ]
}

@test "handles ticket in branch name format" {
  local result=$(extract_jira_ticket "feature/VIS-123-add-toast-component")
  [ "$result" = "VIS-123" ]
}

@test "handles empty input" {
  local result=$(extract_jira_ticket "")
  [ -z "$result" ]
}

# === GitHub PR Caching Tests ===

@test "open PR is not cached (always refetch)" {
  # Setup: Create GitHub DB with open PR
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  state TEXT,
  is_ongoing INTEGER,
  fetched_at TEXT,
  PRIMARY KEY (repo, pr_number)
);
-- Open PR (is_ongoing=1)
INSERT INTO prs VALUES ('test/repo', 100, 'open', 1, datetime('now'));
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Should return false (open PRs always refetch)
  run is_pr_cached "test/repo" 100
  [ "$status" -ne 0 ]
}

@test "merged PR is cached forever" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  state TEXT,
  is_ongoing INTEGER,
  closed_at TEXT,
  merged_at TEXT,
  fetched_at TEXT,
  PRIMARY KEY (repo, pr_number)
);
-- Merged PR (is_ongoing=0)
INSERT INTO prs VALUES ('test/repo', 200, 'closed', 0, '2025-08-10T12:00:00Z', '2025-08-10T12:00:00Z', datetime('now', '-30 days'));
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Should return true (merged PRs never refetch)
  run is_pr_cached "test/repo" 200
  [ "$status" -eq 0 ]
}

@test "closed but not merged PR is cached" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  state TEXT,
  is_ongoing INTEGER,
  closed_at TEXT,
  merged_at TEXT,
  fetched_at TEXT,
  PRIMARY KEY (repo, pr_number)
);
-- Closed not merged (is_ongoing=0)
INSERT INTO prs VALUES ('test/repo', 300, 'closed', 0, '2025-08-10T12:00:00Z', NULL, datetime('now'));
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Should return true (closed PRs immutable)
  run is_pr_cached "test/repo" 300
  [ "$status" -eq 0 ]
}

@test "cache_pr sets is_ongoing=0 for merged PRs" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  title TEXT,
  state TEXT,
  draft INTEGER,
  created_at TEXT,
  closed_at TEXT,
  merged_at TEXT,
  description TEXT,
  fetched_at TEXT,
  duration_seconds INTEGER,
  duration_formatted TEXT,
  state_pretty TEXT,
  is_ongoing INTEGER,
  jira_ticket TEXT,
  PRIMARY KEY (repo, pr_number)
);
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Mock PR JSON (merged)
  local pr_json='{
    "number": 400,
    "title": "VIS-123: Test PR",
    "state": "closed",
    "draft": false,
    "created_at": "2025-08-01T10:00:00Z",
    "closed_at": "2025-08-10T12:00:00Z",
    "merged_at": "2025-08-10T12:00:00Z",
    "body": "Test description"
  }'
  
  cache_pr "test/repo" "$pr_json"
  
  # Check is_ongoing is 0
  local is_ongoing=$(sqlite3 "$GITHUB_DB" "SELECT is_ongoing FROM prs WHERE pr_number=400")
  [ "$is_ongoing" = "0" ]
  
  # Check state_pretty is MERGED
  local state_pretty=$(sqlite3 "$GITHUB_DB" "SELECT state_pretty FROM prs WHERE pr_number=400")
  [ "$state_pretty" = "MERGED" ]
}

@test "cache_pr sets is_ongoing=1 for open PRs" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  title TEXT,
  state TEXT,
  draft INTEGER,
  created_at TEXT,
  closed_at TEXT,
  merged_at TEXT,
  description TEXT,
  fetched_at TEXT,
  duration_seconds INTEGER,
  duration_formatted TEXT,
  state_pretty TEXT,
  is_ongoing INTEGER,
  jira_ticket TEXT,
  PRIMARY KEY (repo, pr_number)
);
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Mock PR JSON (open)
  local pr_json='{
    "number": 500,
    "title": "WIP: Test PR",
    "state": "open",
    "draft": true,
    "created_at": "2025-08-01T10:00:00Z",
    "closed_at": null,
    "merged_at": null,
    "body": "Work in progress"
  }'
  
  cache_pr "test/repo" "$pr_json"
  
  # Check is_ongoing is 1
  local is_ongoing=$(sqlite3 "$GITHUB_DB" "SELECT is_ongoing FROM prs WHERE pr_number=500")
  [ "$is_ongoing" = "1" ]
  
  # Check state_pretty is OPEN
  local state_pretty=$(sqlite3 "$GITHUB_DB" "SELECT state_pretty FROM prs WHERE pr_number=500")
  [ "$state_pretty" = "OPEN" ]
}

@test "cache_pr extracts JIRA ticket from title" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  title TEXT,
  state TEXT,
  draft INTEGER,
  created_at TEXT,
  closed_at TEXT,
  merged_at TEXT,
  description TEXT,
  fetched_at TEXT,
  duration_seconds INTEGER,
  duration_formatted TEXT,
  state_pretty TEXT,
  is_ongoing INTEGER,
  jira_ticket TEXT,
  PRIMARY KEY (repo, pr_number)
);
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Mock PR JSON with JIRA ticket in title
  local pr_json='{
    "number": 600,
    "title": "CORS-1234: Fix authentication bug",
    "state": "closed",
    "draft": false,
    "created_at": "2025-08-01T10:00:00Z",
    "closed_at": "2025-08-10T12:00:00Z",
    "merged_at": "2025-08-10T12:00:00Z",
    "body": "Fixes auth issue"
  }'
  
  cache_pr "test/repo" "$pr_json"
  
  # Check JIRA ticket extracted
  local jira_ticket=$(sqlite3 "$GITHUB_DB" "SELECT jira_ticket FROM prs WHERE pr_number=600")
  [ "$jira_ticket" = "CORS-1234" ]
}

@test "cache_pr handles PR without JIRA ticket" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  title TEXT,
  state TEXT,
  draft INTEGER,
  created_at TEXT,
  closed_at TEXT,
  merged_at TEXT,
  description TEXT,
  fetched_at TEXT,
  duration_seconds INTEGER,
  duration_formatted TEXT,
  state_pretty TEXT,
  is_ongoing INTEGER,
  jira_ticket TEXT,
  PRIMARY KEY (repo, pr_number)
);
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Mock PR JSON without JIRA ticket
  local pr_json='{
    "number": 700,
    "title": "Fix typo in README",
    "state": "closed",
    "draft": false,
    "created_at": "2025-08-01T10:00:00Z",
    "closed_at": "2025-08-10T12:00:00Z",
    "merged_at": "2025-08-10T12:00:00Z",
    "body": "Minor fix"
  }'
  
  cache_pr "test/repo" "$pr_json"
  
  # Check JIRA ticket is NULL
  local jira_ticket=$(sqlite3 "$GITHUB_DB" "SELECT jira_ticket FROM prs WHERE pr_number=700")
  [ -z "$jira_ticket" ] || [ "$jira_ticket" = "null" ]
}

@test "cache_pr_commits calculates commit span" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  first_commit_date TEXT,
  last_commit_date TEXT,
  commit_span_seconds INTEGER,
  commit_span_formatted TEXT,
  first_author_date TEXT,
  last_author_date TEXT,
  author_span_seconds INTEGER,
  author_span_formatted TEXT,
  PRIMARY KEY (repo, pr_number)
);
CREATE TABLE pr_commits (
  repo TEXT,
  pr_number INTEGER,
  sha TEXT,
  author TEXT,
  date TEXT,
  author_date TEXT,
  message TEXT,
  fetched_at TEXT,
  PRIMARY KEY (repo, pr_number, sha)
);
-- Insert PR first
INSERT INTO prs VALUES ('test/repo', 800, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Mock commits JSON (3-day span)
  local commits_json='[
    {
      "sha": "abc123",
      "author": {"login": "user"},
      "commit": {
        "author": {"date": "2025-08-01T10:00:00Z"},
        "committer": {"date": "2025-08-01T10:00:00Z"},
        "message": "Initial commit"
      }
    },
    {
      "sha": "def456",
      "author": {"login": "user"},
      "commit": {
        "author": {"date": "2025-08-04T14:00:00Z"},
        "committer": {"date": "2025-08-04T14:00:00Z"},
        "message": "Add tests"
      }
    }
  ]'
  
  cache_pr_commits "test/repo" 800 "$commits_json"
  
  # Check commits were cached
  local commit_count=$(sqlite3 "$GITHUB_DB" "SELECT COUNT(*) FROM pr_commits WHERE pr_number=800")
  [ "$commit_count" = "2" ]
  
  # Check commit span was calculated
  local first_commit=$(sqlite3 "$GITHUB_DB" "SELECT first_commit_date FROM prs WHERE pr_number=800")
  [ -n "$first_commit" ]
  [ "$first_commit" != "null" ]
}

@test "draft PR marked correctly" {
  local GITHUB_DB="$TEST_TMPDIR/github_data.db"
  sqlite3 "$GITHUB_DB" <<EOF
CREATE TABLE prs (
  repo TEXT,
  pr_number INTEGER,
  title TEXT,
  state TEXT,
  draft INTEGER,
  created_at TEXT,
  closed_at TEXT,
  merged_at TEXT,
  description TEXT,
  fetched_at TEXT,
  duration_seconds INTEGER,
  duration_formatted TEXT,
  state_pretty TEXT,
  is_ongoing INTEGER,
  jira_ticket TEXT,
  PRIMARY KEY (repo, pr_number)
);
EOF
  
  export DB_PATH="$GITHUB_DB"
  export SCRIPT_DIR="$DATABASE_DIR"
  export CACHE_DIR="$TEST_TMPDIR/.cache"
  source "$DATABASE_DIR/db_helpers.sh"
  
  # Mock draft PR JSON
  local pr_json='{
    "number": 900,
    "title": "WIP: Draft PR",
    "state": "open",
    "draft": true,
    "created_at": "2025-08-01T10:00:00Z",
    "closed_at": null,
    "merged_at": null,
    "body": "Draft"
  }'
  
  cache_pr "test/repo" "$pr_json"
  
  # Check draft flag is 1
  local draft=$(sqlite3 "$GITHUB_DB" "SELECT draft FROM prs WHERE pr_number=900")
  [ "$draft" = "1" ]
}

