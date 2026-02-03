#!/bin/bash
# Test helper for github-jira-collector tests
# Provides shared setup, fixtures paths, and isolation guarantees

# === ISOLATION: Prevent accidental writes to real databases ===
unset DATABASE_URL
unset POSTGRES_URL

# === PATHS ===
# Get the directory containing this helper
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
FIXTURES_DIR="$TEST_DIR/fixtures"

# Script paths
SCRIPTS_DIR="$PROJECT_ROOT/lib"
COMPOSE_DIR="$SCRIPTS_DIR/compose"
DATABASE_DIR="$SCRIPTS_DIR/database"

# === FIXTURE HELPERS ===

# Load a JSON fixture file
load_fixture() {
  local name="$1"
  cat "$FIXTURES_DIR/$name"
}

# Create a temp file with fixture content (for scripts that need file paths)
fixture_to_temp() {
  local name="$1"
  local temp_file="$BATS_TMPDIR/$name"
  cp "$FIXTURES_DIR/$name" "$temp_file"
  echo "$temp_file"
}

# === ASSERTION HELPERS ===

# Assert JSON equality (ignoring whitespace differences)
assert_json_equal() {
  local expected="$1"
  local actual="$2"
  
  local expected_normalized=$(echo "$expected" | jq -S '.')
  local actual_normalized=$(echo "$actual" | jq -S '.')
  
  if [ "$expected_normalized" != "$actual_normalized" ]; then
    echo "Expected:"
    echo "$expected_normalized"
    echo "Actual:"
    echo "$actual_normalized"
    return 1
  fi
}

# Assert output contains string
assert_contains() {
  local haystack="$1"
  local needle="$2"
  
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected output to contain: $needle"
    echo "Actual output: $haystack"
    return 1
  fi
}

# Assert file exists
assert_file_exists() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Expected file to exist: $file"
    return 1
  fi
}

# === CLEANUP ===

# Setup function - called before each test
setup() {
  # Create a fresh temp directory for each test
  TEST_TMPDIR=$(mktemp -d "$BATS_TMPDIR/collector-test.XXXXXX")
}

# Teardown function - called after each test
teardown() {
  if [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}
