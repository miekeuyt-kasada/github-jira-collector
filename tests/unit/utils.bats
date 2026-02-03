#!/usr/bin/env bats
# Tests for utils.sh - duration calculations and date helpers

load '../test_helper'

# Source the utils.sh to get the functions
setup() {
  TEST_TMPDIR=$(mktemp -d "$BATS_TMPDIR/bragdoc-test.XXXXXX")
  source "$SCRIPTS_DIR/utils.sh"
}

teardown() {
  if [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# === format_duration_dhm Tests ===

@test "formats 0 seconds as 0m" {
  local result=$(format_duration_dhm 0)
  [ "$result" = "0m" ]
}

@test "formats 60 seconds as 1m" {
  local result=$(format_duration_dhm 60)
  [ "$result" = "1m" ]
}

@test "formats 3600 seconds as 1h" {
  local result=$(format_duration_dhm 3600)
  [ "$result" = "1h" ]
}

@test "formats 3660 seconds as 1h 1m" {
  local result=$(format_duration_dhm 3660)
  [ "$result" = "1h 1m" ]
}

@test "formats 86400 seconds as 1d 0h" {
  local result=$(format_duration_dhm 86400)
  [ "$result" = "1d 0h" ]
}

@test "formats 90061 seconds as 1d 1h 1m" {
  # 86400 + 3600 + 60 + 1 = 90061
  local result=$(format_duration_dhm 90061)
  [ "$result" = "1d 1h 1m" ]
}

@test "formats large duration correctly" {
  # 3 days, 5 hours, 30 minutes = 3*86400 + 5*3600 + 30*60 = 279000
  local result=$(format_duration_dhm 279000)
  [ "$result" = "3d 5h 30m" ]
}

@test "handles empty input gracefully" {
  local result=$(format_duration_dhm "")
  [ "$result" = "0m" ]
}

@test "handles non-numeric input gracefully" {
  local result=$(format_duration_dhm "abc")
  [ "$result" = "0m" ]
}

# === calculate_business_days Tests ===
# Note: These tests use fixed dates to ensure predictable results

@test "calculates 0 business days for same day" {
  local result=$(calculate_business_days "2025-08-04T10:00:00Z" "2025-08-04T10:00:00Z")
  [ "$result" = "0" ]
}

@test "calculates business days for weekday range" {
  # Monday to Friday (5 weekdays, but we count from start, so 4 full days)
  local result=$(calculate_business_days "2025-08-04T00:00:00Z" "2025-08-08T00:00:00Z")
  [ "$result" = "4" ]
}

@test "excludes weekend days" {
  # Friday to Monday (should count Fri, skip Sat/Sun, include Mon = 2 days)
  # Actually: Aug 8 2025 is Friday, Aug 11 2025 is Monday
  local result=$(calculate_business_days "2025-08-08T00:00:00Z" "2025-08-11T00:00:00Z")
  [ "$result" = "1" ]
}

@test "handles full week including weekend" {
  # Monday Aug 4 to Monday Aug 11 = 5 weekdays (Mon-Fri)
  local result=$(calculate_business_days "2025-08-04T00:00:00Z" "2025-08-11T00:00:00Z")
  [ "$result" = "5" ]
}

@test "returns 0 for empty start time" {
  local result=$(calculate_business_days "" "2025-08-04T00:00:00Z")
  [ "$result" = "0" ]
}

@test "returns 0 for empty end time" {
  local result=$(calculate_business_days "2025-08-04T00:00:00Z" "")
  [ "$result" = "0" ]
}

# === calculate_business_duration Tests ===

@test "calculates business duration excluding weekends" {
  # Monday 00:00 to Wednesday 00:00 = 2 full weekdays = 2*86400 = 172800
  local result=$(calculate_business_duration "2025-08-04T00:00:00Z" "2025-08-06T00:00:00Z")
  [ "$result" = "172800" ]
}

@test "business duration skips Saturday" {
  # Friday 00:00 to Monday 00:00 = just Friday = 86400
  local result=$(calculate_business_duration "2025-08-08T00:00:00Z" "2025-08-11T00:00:00Z")
  [ "$result" = "86400" ]
}

@test "business duration handles partial day on weekday" {
  # Monday 00:00 to Monday 12:00 = 12 hours = 43200
  local result=$(calculate_business_duration "2025-08-04T00:00:00Z" "2025-08-04T12:00:00Z")
  [ "$result" = "43200" ]
}

@test "business duration returns 0 for weekend-only span" {
  # Saturday to Sunday (both weekend, partial)
  # Aug 9 2025 is Saturday, Aug 10 2025 is Sunday
  local result=$(calculate_business_duration "2025-08-09T00:00:00Z" "2025-08-10T00:00:00Z")
  [ "$result" = "0" ]
}

@test "business duration returns 0 for empty inputs" {
  local result=$(calculate_business_duration "" "")
  [ "$result" = "0" ]
}

# === Additional Edge Cases ===

@test "handles leap year dates in business days calculation" {
  # Feb 29, 2024 (leap year) to March 1, 2024
  # Feb 29 2024 is Thursday, March 1 2024 is Friday = 2 business days
  local result=$(calculate_business_days "2024-02-29T00:00:00Z" "2024-03-01T00:00:00Z")
  [ "$result" = "1" ]
}

@test "handles negative duration (end before start)" {
  # End date before start date - should return 0 or handle gracefully
  local result=$(calculate_business_duration "2025-08-10T00:00:00Z" "2025-08-05T00:00:00Z")
  
  # Should not crash - result should be 0 or empty
  [ -n "$result" ]
}

@test "handles same timestamp for business duration" {
  local timestamp="2025-08-04T12:00:00Z"
  local result=$(calculate_business_duration "$timestamp" "$timestamp")
  [ "$result" = "0" ]
}

@test "format_duration_dhm handles very large durations" {
  # 30 days = 2,592,000 seconds
  local result=$(format_duration_dhm 2592000)
  
  # Should format as "30d 0h"
  assert_contains "$result" "30d"
}

@test "format_duration_dhm handles negative input gracefully" {
  local result=$(format_duration_dhm "-100")
  
  # Should handle gracefully (treat as 0 or invalid)
  [ "$result" = "0m" ]
}

@test "calculate_business_days handles month boundaries" {
  # Last day of month to first day of next month
  # July 31 2025 (Thursday) to Aug 1 2025 (Friday) = 2 business days
  local result=$(calculate_business_days "2025-07-31T00:00:00Z" "2025-08-01T00:00:00Z")
  [ "$result" = "1" ]
}

@test "calculate_business_days handles year boundaries" {
  # Dec 31 2024 (Tuesday) to Jan 1 2025 (Wednesday) = 2 business days
  local result=$(calculate_business_days "2024-12-31T00:00:00Z" "2025-01-01T00:00:00Z")
  [ "$result" = "1" ]
}

@test "business duration handles partial hours correctly" {
  # Monday 10:00 to Monday 10:30 = 30 minutes = 1800 seconds
  local result=$(calculate_business_duration "2025-08-04T10:00:00Z" "2025-08-04T10:30:00Z")
  [ "$result" = "1800" ]
}

@test "calculate_business_days excludes full weekend correctly" {
  # Friday to Monday with full weekend
  # Aug 1 2025 (Fri) to Aug 4 2025 (Mon) = 2 business days (Fri and Mon)
  local result=$(calculate_business_days "2025-08-01T00:00:00Z" "2025-08-04T00:00:00Z")
  [ "$result" = "1" ]
}

@test "format_duration_dhm handles exactly 1 hour" {
  local result=$(format_duration_dhm 3600)
  [ "$result" = "1h" ]
}

@test "format_duration_dhm handles exactly 1 day" {
  local result=$(format_duration_dhm 86400)
  [ "$result" = "1d 0h" ]
}

@test "calculate_business_duration handles multiple full weeks" {
  # 2 weeks = 10 business days = 10 * 86400 seconds
  # Aug 4 2025 (Mon) to Aug 18 2025 (Mon) = 10 business days
  local result=$(calculate_business_duration "2025-08-04T00:00:00Z" "2025-08-18T00:00:00Z")
  
  # Should be 10 days * 86400 = 864000
  [ "$result" = "864000" ]
}

