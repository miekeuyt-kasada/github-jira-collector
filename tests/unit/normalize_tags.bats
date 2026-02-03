#!/usr/bin/env bats
# Tests for normalize_tags.sh - tag normalization and validation utilities

load '../test_helper'

# Source the normalize_tags.sh to get the functions
setup() {
  TEST_TMPDIR=$(mktemp -d "$BATS_TMPDIR/bragdoc-test.XXXXXX")
  source "$SCRIPTS_DIR/utils/normalize_tags.sh"
}

teardown() {
  if [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# === normalize_company_goal_tag Tests ===

@test "normalizes 'Deliver a positive impact' to kebab-case" {
  local result=$(normalize_company_goal_tag "Deliver a positive impact")
  [ "$result" = "positive-impact" ]
}

@test "normalizes 'Be bold, collaborate and innovate' to kebab-case" {
  local result=$(normalize_company_goal_tag "Be bold, collaborate and innovate")
  [ "$result" = "collaborate-and-innovate" ]
}

@test "normalizes 'Seek to understand' to kebab-case" {
  local result=$(normalize_company_goal_tag "Seek to understand")
  [ "$result" = "seek-to-understand" ]
}

@test "normalizes 'Trust and confidentiality' to kebab-case" {
  local result=$(normalize_company_goal_tag "Trust and confidentiality")
  [ "$result" = "trust-and-confidentiality" ]
}

@test "normalizes 'Embrace differences and empower others' to kebab-case" {
  local result=$(normalize_company_goal_tag "Embrace differences and empower others")
  [ "$result" = "embrace-differences-and-empower-others" ]
}

@test "handles already kebab-case company goal (passthrough)" {
  local result=$(normalize_company_goal_tag "positive-impact")
  [ "$result" = "positive-impact" ]
}

@test "handles uppercase company goal input" {
  local result=$(normalize_company_goal_tag "DELIVER A POSITIVE IMPACT")
  [ "$result" = "positive-impact" ]
}

@test "handles mixed case company goal input" {
  local result=$(normalize_company_goal_tag "DeLiVeR a PoSiTiVe ImPaCt")
  [ "$result" = "positive-impact" ]
}

@test "returns unknown company goal as-is" {
  local result=$(normalize_company_goal_tag "Unknown Goal")
  [ "$result" = "Unknown Goal" ]
}

# === normalize_growth_area_tag Tests ===

@test "normalizes 'Goal Oriented' to kebab-case" {
  local result=$(normalize_growth_area_tag "Goal Oriented")
  [ "$result" = "goal-oriented" ]
}

@test "normalizes 'Decision Making' to kebab-case" {
  local result=$(normalize_growth_area_tag "Decision Making")
  [ "$result" = "decision-making" ]
}

@test "normalizes 'Persistence' to kebab-case" {
  local result=$(normalize_growth_area_tag "Persistence")
  [ "$result" = "persistence" ]
}

@test "normalizes 'Personal Accountability' to kebab-case" {
  local result=$(normalize_growth_area_tag "Personal Accountability")
  [ "$result" = "personal-accountability" ]
}

@test "normalizes 'Growth Mindset' to kebab-case" {
  local result=$(normalize_growth_area_tag "Growth Mindset")
  [ "$result" = "growth-mindset" ]
}

@test "normalizes 'Empathy' to kebab-case" {
  local result=$(normalize_growth_area_tag "Empathy")
  [ "$result" = "empathy" ]
}

@test "normalizes 'Communication & Collaboration' to kebab-case" {
  local result=$(normalize_growth_area_tag "Communication & Collaboration")
  [ "$result" = "communication-and-collaboration" ]
}

@test "normalizes 'Communication and Collaboration' (and variant) to kebab-case" {
  local result=$(normalize_growth_area_tag "Communication and Collaboration")
  [ "$result" = "communication-and-collaboration" ]
}

@test "normalizes 'Curiosity' to kebab-case" {
  local result=$(normalize_growth_area_tag "Curiosity")
  [ "$result" = "curiosity" ]
}

@test "normalizes 'Customer Empathy' to kebab-case" {
  local result=$(normalize_growth_area_tag "Customer Empathy")
  [ "$result" = "customer-empathy" ]
}

@test "handles already kebab-case growth area (passthrough)" {
  local result=$(normalize_growth_area_tag "decision-making")
  [ "$result" = "decision-making" ]
}

@test "handles uppercase growth area input" {
  local result=$(normalize_growth_area_tag "DECISION MAKING")
  [ "$result" = "decision-making" ]
}

@test "handles mixed case growth area input" {
  local result=$(normalize_growth_area_tag "DeCiSiOn MaKiNg")
  [ "$result" = "decision-making" ]
}

@test "returns unknown growth area as-is" {
  local result=$(normalize_growth_area_tag "Unknown Area")
  [ "$result" = "Unknown Area" ]
}

# === validate_company_goal_tag Tests ===

@test "validates positive-impact as valid company goal" {
  validate_company_goal_tag "positive-impact"
  [ $? -eq 0 ]
}

@test "validates collaborate-and-innovate as valid company goal" {
  validate_company_goal_tag "collaborate-and-innovate"
  [ $? -eq 0 ]
}

@test "validates seek-to-understand as valid company goal" {
  validate_company_goal_tag "seek-to-understand"
  [ $? -eq 0 ]
}

@test "validates trust-and-confidentiality as valid company goal" {
  validate_company_goal_tag "trust-and-confidentiality"
  [ $? -eq 0 ]
}

@test "validates embrace-differences-and-empower-others as valid company goal" {
  validate_company_goal_tag "embrace-differences-and-empower-others"
  [ $? -eq 0 ]
}

@test "rejects invalid company goal tag" {
  run validate_company_goal_tag "invalid-goal"
  [ "$status" -eq 1 ]
}

@test "rejects title-case company goal tag" {
  run validate_company_goal_tag "Deliver a positive impact"
  [ "$status" -eq 1 ]
}

# === validate_growth_area_tag Tests ===

@test "validates goal-oriented as valid growth area" {
  validate_growth_area_tag "goal-oriented"
  [ $? -eq 0 ]
}

@test "validates decision-making as valid growth area" {
  validate_growth_area_tag "decision-making"
  [ $? -eq 0 ]
}

@test "validates persistence as valid growth area" {
  validate_growth_area_tag "persistence"
  [ $? -eq 0 ]
}

@test "validates personal-accountability as valid growth area" {
  validate_growth_area_tag "personal-accountability"
  [ $? -eq 0 ]
}

@test "validates growth-mindset as valid growth area" {
  validate_growth_area_tag "growth-mindset"
  [ $? -eq 0 ]
}

@test "validates empathy as valid growth area" {
  validate_growth_area_tag "empathy"
  [ $? -eq 0 ]
}

@test "validates communication-and-collaboration as valid growth area" {
  validate_growth_area_tag "communication-and-collaboration"
  [ $? -eq 0 ]
}

@test "validates curiosity as valid growth area" {
  validate_growth_area_tag "curiosity"
  [ $? -eq 0 ]
}

@test "validates customer-empathy as valid growth area" {
  validate_growth_area_tag "customer-empathy"
  [ $? -eq 0 ]
}

@test "rejects invalid growth area tag" {
  run validate_growth_area_tag "invalid-area"
  [ "$status" -eq 1 ]
}

@test "rejects title-case growth area tag" {
  run validate_growth_area_tag "Decision Making"
  [ "$status" -eq 1 ]
}

# === normalize_company_goals_json Tests ===

@test "normalizes JSON array of company goals" {
  local input='[{"tag": "Deliver a positive impact", "description": "test"}]'
  local result=$(normalize_company_goals_json "$input")
  local normalized_tag=$(echo "$result" | jq -r '.[0].tag')
  [ "$normalized_tag" = "positive-impact" ]
}

@test "normalizes multiple company goals in array" {
  local input='[
    {"tag": "Deliver a positive impact", "description": "test1"},
    {"tag": "Seek to understand", "description": "test2"}
  ]'
  local result=$(normalize_company_goals_json "$input")
  local tag1=$(echo "$result" | jq -r '.[0].tag')
  local tag2=$(echo "$result" | jq -r '.[1].tag')
  [ "$tag1" = "positive-impact" ]
  [ "$tag2" = "seek-to-understand" ]
}

@test "preserves descriptions when normalizing company goals" {
  local input='[{"tag": "Deliver a positive impact", "description": "Original description"}]'
  local result=$(normalize_company_goals_json "$input")
  local desc=$(echo "$result" | jq -r '.[0].description')
  [ "$desc" = "Original description" ]
}

@test "handles already normalized company goals in JSON" {
  local input='[{"tag": "positive-impact", "description": "test"}]'
  local result=$(normalize_company_goals_json "$input")
  local tag=$(echo "$result" | jq -r '.[0].tag')
  [ "$tag" = "positive-impact" ]
}

@test "handles empty company goals array" {
  local input='[]'
  local result=$(normalize_company_goals_json "$input")
  [ "$result" = "[]" ]
}

@test "handles company goals with special characters in description" {
  local input='[{"tag": "Deliver a positive impact", "description": "Test with \"quotes\" and '\''apostrophes'\''"}]'
  local result=$(normalize_company_goals_json "$input")
  local desc=$(echo "$result" | jq -r '.[0].description')
  [[ "$desc" == *"quotes"* ]]
}

# === normalize_growth_areas_json Tests ===

@test "normalizes JSON array of growth areas" {
  local input='[{"tag": "Decision Making", "description": "test"}]'
  local result=$(normalize_growth_areas_json "$input")
  local normalized_tag=$(echo "$result" | jq -r '.[0].tag')
  [ "$normalized_tag" = "decision-making" ]
}

@test "normalizes multiple growth areas in array" {
  local input='[
    {"tag": "Goal Oriented", "description": "test1"},
    {"tag": "Empathy", "description": "test2"}
  ]'
  local result=$(normalize_growth_areas_json "$input")
  local tag1=$(echo "$result" | jq -r '.[0].tag')
  local tag2=$(echo "$result" | jq -r '.[1].tag')
  [ "$tag1" = "goal-oriented" ]
  [ "$tag2" = "empathy" ]
}

@test "handles communication variant with ampersand" {
  local input='[{"tag": "Communication & Collaboration", "description": "test"}]'
  local result=$(normalize_growth_areas_json "$input")
  local tag=$(echo "$result" | jq -r '.[0].tag')
  [ "$tag" = "communication-and-collaboration" ]
}

@test "handles communication variant with 'and'" {
  local input='[{"tag": "Communication and Collaboration", "description": "test"}]'
  local result=$(normalize_growth_areas_json "$input")
  local tag=$(echo "$result" | jq -r '.[0].tag')
  [ "$tag" = "communication-and-collaboration" ]
}

@test "preserves descriptions when normalizing growth areas" {
  local input='[{"tag": "Decision Making", "description": "Original description"}]'
  local result=$(normalize_growth_areas_json "$input")
  local desc=$(echo "$result" | jq -r '.[0].description')
  [ "$desc" = "Original description" ]
}

@test "handles already normalized growth areas in JSON" {
  local input='[{"tag": "decision-making", "description": "test"}]'
  local result=$(normalize_growth_areas_json "$input")
  local tag=$(echo "$result" | jq -r '.[0].tag')
  [ "$tag" = "decision-making" ]
}

@test "handles empty growth areas array" {
  local input='[]'
  local result=$(normalize_growth_areas_json "$input")
  [ "$result" = "[]" ]
}

@test "handles growth areas with special characters in description" {
  local input='[{"tag": "Empathy", "description": "Test with \"quotes\" and special chars: @#$"}]'
  local result=$(normalize_growth_areas_json "$input")
  local desc=$(echo "$result" | jq -r '.[0].description')
  [[ "$desc" == *"quotes"* ]]
}

# === get_valid_company_goals Tests ===

@test "get_valid_company_goals returns all 5 goals" {
  local goals=$(get_valid_company_goals)
  local count=$(echo "$goals" | wc -l | tr -d ' ')
  [ "$count" = "5" ]
}

@test "get_valid_company_goals includes positive-impact" {
  local goals=$(get_valid_company_goals)
  echo "$goals" | grep -q "positive-impact"
}

@test "get_valid_company_goals includes all expected goals" {
  local goals=$(get_valid_company_goals)
  echo "$goals" | grep -q "positive-impact"
  echo "$goals" | grep -q "collaborate-and-innovate"
  echo "$goals" | grep -q "seek-to-understand"
  echo "$goals" | grep -q "trust-and-confidentiality"
  echo "$goals" | grep -q "embrace-differences-and-empower-others"
}

# === get_valid_growth_areas Tests ===

@test "get_valid_growth_areas returns all 9 areas" {
  local areas=$(get_valid_growth_areas)
  local count=$(echo "$areas" | wc -l | tr -d ' ')
  [ "$count" = "9" ]
}

@test "get_valid_growth_areas includes decision-making" {
  local areas=$(get_valid_growth_areas)
  echo "$areas" | grep -q "decision-making"
}

@test "get_valid_growth_areas includes all expected areas" {
  local areas=$(get_valid_growth_areas)
  echo "$areas" | grep -q "goal-oriented"
  echo "$areas" | grep -q "decision-making"
  echo "$areas" | grep -q "persistence"
  echo "$areas" | grep -q "personal-accountability"
  echo "$areas" | grep -q "growth-mindset"
  echo "$areas" | grep -q "empathy"
  echo "$areas" | grep -q "communication-and-collaboration"
  echo "$areas" | grep -q "curiosity"
  echo "$areas" | grep -q "customer-empathy"
}
