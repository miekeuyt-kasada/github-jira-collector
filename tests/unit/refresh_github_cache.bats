#!/usr/bin/env bats
# Tests for 00_refresh_github_cache.sh

load '../test_helper'

SCRIPT="$STEPS_DIR/00_refresh_github_cache.sh"

setup() {
  TEST_TMPDIR=$(mktemp -d "$BATS_TMPDIR/cache-test.XXXXXX")
  
  # Create isolated mock project
  MOCK_PROJECT="$TEST_TMPDIR/mock-project"
  mkdir -p "$MOCK_PROJECT/steps"
  mkdir -p "$MOCK_PROJECT/github-summary/scripts/.cache"
  
  # Copy the actual script we're testing
  cp "$STEPS_DIR/00_refresh_github_cache.sh" "$MOCK_PROJECT/steps/"
  
  # Create mock get_github_data.sh
  cat > "$MOCK_PROJECT/github-summary/scripts/get_github_data.sh" <<'EOF'
#!/bin/bash
# Mock that creates test DB with data
CACHE_DIR="$(dirname "$0")/.cache"
DB="$CACHE_DIR/github_data.db"
START_DATE="$2"

sqlite3 "$DB" <<SQL
CREATE TABLE IF NOT EXISTS prs (repo TEXT, pr_number INT, created_at TEXT);
CREATE TABLE IF NOT EXISTS direct_commits (repo TEXT, sha TEXT, date TEXT);
INSERT INTO prs VALUES ('test/repo', 100, '$START_DATE');
SQL
echo "✅ Report generated"
EOF
  chmod +x "$MOCK_PROJECT/github-summary/scripts/get_github_data.sh"
  
  MOCK_DB="$MOCK_PROJECT/github-summary/scripts/.cache/github_data.db"
}

@test "script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "skips fetch when cache has data" {
  # Create DB with existing data
  sqlite3 "$MOCK_DB" <<EOF
CREATE TABLE prs (repo TEXT, pr_number INT, created_at TEXT);
INSERT INTO prs VALUES ('test/repo', 100, '2025-07-01T10:00:00Z');
CREATE TABLE direct_commits (repo TEXT, sha TEXT, date TEXT);
EOF
  
  # Run from mock project
  cd "$MOCK_PROJECT"
  run ./steps/00_refresh_github_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "Cache already has"
  assert_contains "$output" "items for 2025-07"
}

@test "fetches when cache is empty" {
  # No DB exists
  cd "$MOCK_PROJECT"
  run ./steps/00_refresh_github_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "No cache found"
  assert_contains "$output" "Fetching from GitHub API"
}

@test "fetches when cache has no data for month" {
  # Create DB with data for different month
  sqlite3 "$MOCK_DB" <<EOF
CREATE TABLE prs (repo TEXT, pr_number INT, created_at TEXT);
INSERT INTO prs VALUES ('test/repo', 999, '2025-06-01T10:00:00Z');
CREATE TABLE direct_commits (repo TEXT, sha TEXT, date TEXT);
EOF
  
  cd "$MOCK_PROJECT"
  run ./steps/00_refresh_github_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "No cached data for 2025-07"
}

@test "forces refresh with --force flag" {
  # Create DB with existing data
  sqlite3 "$MOCK_DB" <<EOF
CREATE TABLE prs (repo TEXT, pr_number INT, created_at TEXT);
INSERT INTO prs VALUES ('test/repo', 100, '2025-07-01T10:00:00Z');
CREATE TABLE direct_commits (repo TEXT, sha TEXT, date TEXT);
EOF
  
  cd "$MOCK_PROJECT"
  run ./steps/00_refresh_github_cache.sh "2025-07" "2025-07-01" "2025-08-01" "--force"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "Force refresh requested"
  assert_contains "$output" "Re-fetching from GitHub API"
}

@test "reports correct counts after fetch" {
  cd "$MOCK_PROJECT"
  run ./steps/00_refresh_github_cache.sh "2025-07" "2025-07-01" "2025-08-01"
  
  [ "$status" -eq 0 ]
  assert_contains "$output" "Cache refreshed:"
  assert_contains "$output" "items for 2025-07"
}

@test "fails with wrong number of arguments" {
  cd "$MOCK_PROJECT"
  run ./steps/00_refresh_github_cache.sh "2025-07"
  [ "$status" -ne 0 ]
}
