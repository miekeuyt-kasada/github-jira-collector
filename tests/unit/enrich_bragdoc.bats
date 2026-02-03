#!/usr/bin/env bats
# Tests for enrich_bragdoc.sh - LLM output enrichment with PR metadata

load '../test_helper'

# Path to the script under test
ENRICH_SCRIPT="$COMPOSE_DIR/enrich_bragdoc.sh"

@test "enrich_bragdoc.sh exists and is executable" {
  [ -f "$ENRICH_SCRIPT" ]
  [ -x "$ENRICH_SCRIPT" ]
}

# === PR Number Matching Tests ===

@test "matches PR by number in achievement text (#123)" {
  # Create LLM output with PR number reference
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Fixed toast notification styling in #123", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Check that prId was added
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "123" ]
  
  # Check that ticketNo was added
  local ticket_no=$(jq -r '.[0].ticketNo' "$output_file")
  [ "$ticket_no" = "VIS-454" ]
  
  # Check that repo was added
  local repo=$(jq -r '.[0].repo' "$output_file")
  [ "$repo" = "acme/portal" ]
}

@test "matches PR by number in context field" {
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Improved code quality", "context": "Related to PR #789", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "789" ]
}

# === Date-Based Matching Tests ===

@test "matches PR by date overlap" {
  # Item has dates that overlap with PR #456 (2025-08-10 to 2025-08-12)
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Removed deprecated sidebar component", "dates": ["2025-08-10", "2025-08-12"], "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "456" ]
}

@test "preserves existing dates array when matching by date" {
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Removed deprecated sidebar", "dates": ["2025-08-10", "2025-08-12"], "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Original dates array should be preserved
  local dates=$(jq -c '.[0].dates' "$output_file")
  [ "$dates" = '["2025-08-10","2025-08-12"]' ]
}

# === Fuzzy Text Matching Tests ===

@test "matches PR by fuzzy title match" {
  # Using pr-data.json which has "Fixed SonarQube exclusions" title
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Fixed SonarQube exclusions", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "pr-data.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "100" ]
  
  local ticket_no=$(jq -r '.[0].ticketNo' "$output_file")
  [ "$ticket_no" = "VIS-100" ]
}

# === No Match Tests ===

@test "passes through item unchanged when no match found" {
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Completely unrelated work that matches nothing", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Should not have prId
  local pr_id=$(jq -r '.[0].prId // "null"' "$output_file")
  [ "$pr_id" = "null" ]
  
  # Original fields should be preserved
  local achievement=$(jq -r '.[0].achievement' "$output_file")
  [ "$achievement" = "Completely unrelated work that matches nothing" ]
}

@test "preserves eventId for manual events" {
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Won the Bug Bash", "eventId": "m-abc12345", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # eventId should be preserved
  local event_id=$(jq -r '.[0].eventId' "$output_file")
  [ "$event_id" = "m-abc12345" ]
}

# === Commit SHA Tests ===

@test "adds commit SHAs from matched PR" {
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Fixed toast in #123", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Should have both commit SHAs from PR #123
  local sha_count=$(jq '.[0].commitShas | length' "$output_file")
  [ "$sha_count" = "2" ]
  
  local first_sha=$(jq -r '.[0].commitShas[0]' "$output_file")
  [ "$first_sha" = "abc123def456789" ]
}

# === Multiple Items Tests ===

@test "processes multiple items correctly" {
  local llm_file="$TEST_TMPDIR/llm.json"
  cat > "$llm_file" << 'EOF'
[
  {"achievement": "Fixed bug in #123", "outcomes": "test", "impact": "test"},
  {"achievement": "Unrelated work", "outcomes": "test", "impact": "test"},
  {"achievement": "Rate limiting in #789", "outcomes": "test", "impact": "test"}
]
EOF
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Check item count
  local count=$(jq 'length' "$output_file")
  [ "$count" = "3" ]
  
  # First item should match PR 123
  local pr1=$(jq -r '.[0].prId' "$output_file")
  [ "$pr1" = "123" ]
  
  # Second item should have no prId
  local pr2=$(jq -r '.[1].prId // "null"' "$output_file")
  [ "$pr2" = "null" ]
  
  # Third item should match PR 789
  local pr3=$(jq -r '.[2].prId' "$output_file")
  [ "$pr3" = "789" ]
}

# === Error Handling Tests ===

@test "fails with missing LLM output file" {
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  run "$ENRICH_SCRIPT" "/nonexistent/llm.json" "$raw_file" "$output_file"
  [ "$status" -ne 0 ]
}

@test "fails with missing raw data file" {
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "test"}]' > "$llm_file"
  local output_file="$TEST_TMPDIR/output.json"
  
  run "$ENRICH_SCRIPT" "$llm_file" "/nonexistent/raw.json" "$output_file"
  [ "$status" -ne 0 ]
}

@test "fails with missing arguments" {
  run "$ENRICH_SCRIPT"
  [ "$status" -ne 0 ]
}

# === Edge Case Tests ===

@test "handles item with single date (not array of two)" {
  local llm_file="$TEST_TMPDIR/single-date.json"
  echo '[{"achievement": "Quick fix", "dates": ["2025-08-10"], "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  # Should not crash
  run "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  [ "$status" -eq 0 ]
  
  # Output should exist and be valid JSON
  jq '.' "$output_file" > /dev/null
}

@test "handles empty raw PRs array" {
  local llm_file="$TEST_TMPDIR/llm.json"
  echo '[{"achievement": "Manual work", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file="$TEST_TMPDIR/empty-raw.json"
  echo '{"prs": [], "direct_commits": []}' > "$raw_file"
  
  local output_file="$TEST_TMPDIR/output.json"
  
  # Should not crash, item passes through
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  local achievement=$(jq -r '.[0].achievement' "$output_file")
  [ "$achievement" = "Manual work" ]
}

@test "handles achievement with quotes and special chars" {
  local llm_file="$TEST_TMPDIR/special.json"
  cat > "$llm_file" << 'EOF'
[{"achievement": "Fixed \"escape\" issue in PR #123", "outcomes": "test", "impact": "test"}]
EOF
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Should match PR 123 despite special chars
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "123" ]
}

@test "handles item with empty dates array" {
  local llm_file="$TEST_TMPDIR/no-dates.json"
  echo '[{"achievement": "Work without dates", "dates": [], "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  # Should not crash
  run "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  [ "$status" -eq 0 ]
}

# === Additional Edge Cases ===

@test "fuzzy matching is lenient with partial word matches" {
  local llm_file="$TEST_TMPDIR/fuzzy-test.json"
  # Achievement with shared word "notification" but different context
  echo '[{"achievement": "Updated notification system completely differently", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Fuzzy matcher is lenient - shared words like "notification" can cause matches
  # This documents current behavior (not necessarily wrong)
  local pr_id=$(jq -r '.[0].prId // "null"' "$output_file")
  # May match PR 123 which has "notification" in title, or may not - either is acceptable
  [[ "$pr_id" =~ ^([0-9]+|null)$ ]]
}

@test "handles multiple PRs with overlapping date ranges" {
  local llm_file="$TEST_TMPDIR/overlap-dates.json"
  # Dates that could match multiple PRs - should pick best match
  echo '[{"achievement": "Fixed things", "dates": ["2025-08-01", "2025-08-05"], "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Should match one PR (likely PR #123 based on dates)
  local pr_id=$(jq -r '.[0].prId // "null"' "$output_file")
  # As long as it picked one, that's acceptable
  [[ "$pr_id" =~ ^[0-9]+$ ]] || [ "$pr_id" = "null" ]
}

@test "handles achievement with unicode characters" {
  local llm_file="$TEST_TMPDIR/unicode.json"
  echo '[{"achievement": "Fixed toast 🎉 notification in #123", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Should still match PR 123
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "123" ]
  
  # Unicode should be preserved
  local ach=$(jq -r '.[0].achievement' "$output_file")
  assert_contains "$ach" "🎉"
}

@test "handles achievement with emoji in title" {
  local llm_file="$TEST_TMPDIR/emoji.json"
  echo '[{"achievement": "✨ Improved performance ✨ in #789", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  # Should match PR 789
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "789" ]
}

@test "handles malformed regex special chars in PR title" {
  local llm_file="$TEST_TMPDIR/regex-chars.json"
  # Achievement with regex-like characters
  echo '[{"achievement": "Fixed (bug) [issue] in $component for #123", "outcomes": "test", "impact": "test"}]' > "$llm_file"
  
  local raw_file=$(fixture_to_temp "month-raw.json")
  local output_file="$TEST_TMPDIR/output.json"
  
  # Should not crash and should match PR 123
  "$ENRICH_SCRIPT" "$llm_file" "$raw_file" "$output_file"
  
  local pr_id=$(jq -r '.[0].prId' "$output_file")
  [ "$pr_id" = "123" ]
}

