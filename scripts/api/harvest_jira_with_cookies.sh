#!/bin/bash
# Harvest Jira custom fields using browser session cookies
# Usage: 
#   1. Copy cookies from browser DevTools (see instructions below)
#   2. Paste into JIRA_COOKIES variable below
#   3. Run: ./harvest_jira_with_cookies.sh

set -euo pipefail

# INSTRUCTIONS:
# 1. Open Jira in your browser (kasada.atlassian.net)
# 2. Open DevTools (F12) → Network tab
# 3. Refresh the page
# 4. Right-click any request → Copy → Copy as cURL
# 5. Extract the -b '...' part (the cookies string)
# 6. Paste it below (between the quotes)

JIRA_COOKIES="${JIRA_COOKIES:-}"

if [ -z "$JIRA_COOKIES" ]; then
  echo "❌ Error: JIRA_COOKIES not set"
  echo ""
  echo "To set cookies:"
  echo "  1. Copy a cURL command from DevTools (see script comments)"
  echo "  2. Extract the cookie string from -b '...'"
  echo "  3. Run: export JIRA_COOKIES='your-cookie-string'"
  echo "  4. Run this script again"
  echo ""
  echo "Or set it in .env.local:"
  echo "  JIRA_COOKIES='your-cookie-string'"
  exit 1
fi

JIRA_BASE_URL="${JIRA_BASE_URL:-https://kasada.atlassian.net}"
CLOUD_ID="${JIRA_CLOUD_ID:-b633e431-9232-422a-8a3e-097525c8a8fb}"

# Get database path
DB_PATH="${1:-github-summary/.cache/github_report.db}"
LIMIT="${2:-5}"

if [ ! -f "$DB_PATH" ]; then
  echo "❌ Error: Database not found at $DB_PATH"
  exit 1
fi

echo "🔍 Harvesting custom fields using browser cookies..."
echo "⚠️  Testing mode: sampling first $LIMIT issues"
echo ""

# Get Jira tickets from database
jira_tickets=$(sqlite3 "$DB_PATH" "SELECT DISTINCT jira_ticket FROM prs WHERE jira_ticket IS NOT NULL AND jira_ticket != '' ORDER BY jira_ticket LIMIT $LIMIT;" 2>/dev/null || echo "")

if [ -z "$jira_tickets" ]; then
  echo "❌ No Jira tickets found in database"
  exit 1
fi

ticket_count=$(echo "$jira_tickets" | wc -l | tr -d ' ')
echo "📊 Found $ticket_count tickets to sample"
echo ""

# Create temp directory for results
temp_dir=$(mktemp -d)
all_fields_file="$temp_dir/all_fields.json"
echo "[]" > "$all_fields_file"

echo "🌐 Fetching issue details from Jira..."
processed=0
succeeded=0
failed=0

echo "$jira_tickets" | while read -r ticket; do
  if [ -z "$ticket" ]; then
    continue
  fi
  
  processed=$((processed + 1))
  echo -n "   [$processed/$ticket_count] $ticket ... "
  
  # Fetch issue using REST API with cookies
  response=$(curl -s -X GET \
    "$JIRA_BASE_URL/rest/api/3/issue/$ticket" \
    -H "Accept: application/json" \
    -b "$JIRA_COOKIES" 2>/dev/null || echo '{"error": true}')
  
  # Check for errors
  if echo "$response" | jq -e '.errorMessages' > /dev/null 2>&1; then
    error_msg=$(echo "$response" | jq -r '.errorMessages[0]' 2>/dev/null | head -c 40)
    echo "❌ $error_msg"
    failed=$((failed + 1))
    continue
  fi
  
  if ! echo "$response" | jq -e '.fields' > /dev/null 2>&1; then
    echo "❌ No fields"
    failed=$((failed + 1))
    continue
  fi
  
  # Extract custom field IDs
  custom_fields=$(echo "$response" | jq -r '.fields | to_entries[] | select(.key | startswith("customfield_")) | {id: .key, value: .value, type: (.value | type)}' 2>/dev/null || echo "")
  
  if [ -n "$custom_fields" ]; then
    echo "$custom_fields" | jq -s '.' > "$temp_dir/fields_$ticket.json"
    succeeded=$((succeeded + 1))
    echo "✅ Found $(echo "$custom_fields" | wc -l | tr -d ' ') custom fields"
  else
    echo "⚠️  No custom fields"
  fi
  
  sleep 0.3
done

echo ""
echo "📦 Aggregating and deduplicating..."

# Combine all field files
cat "$temp_dir"/fields_*.json 2>/dev/null | jq -s 'add | unique_by(.id)' > "$all_fields_file" 2>/dev/null || echo "[]" > "$all_fields_file"

# Try to get field metadata for names
echo "📋 Fetching field metadata..."
metadata_response=$(curl -s -X GET \
  "$JIRA_BASE_URL/rest/api/3/field" \
  -H "Accept: application/json" \
  -b "$JIRA_COOKIES" 2>/dev/null || echo "[]")

echo ""
echo "✅ Custom fields discovered:"
echo ""

field_count=$(jq -r 'length' "$all_fields_file")
if [ "$field_count" -eq 0 ]; then
  echo "   No custom fields found"
else
  jq -r '.[] | .id' "$all_fields_file" | sort -u | while read -r field_id; do
    # Get field name from metadata
    field_name=$(echo "$metadata_response" | jq -r ".[] | select(.id == \"$field_id\") | .name" 2>/dev/null || echo "Unknown")
    
    # Get sample values (non-null)
    sample_values=$(jq -r ".[] | select(.id == \"$field_id\" and .value != null) | .value | if type == \"object\" then .name // .displayName // .value // \"[object]\" elif type == \"array\" then (if length > 0 then (.[0].name // .[0].value // \"[array]\") else \"[empty array]\" end) else tostring end" "$all_fields_file" 2>/dev/null | sort -u | head -n 3)
    
    echo "   $field_id"
    echo "      Name: $field_name"
    if [ -n "$sample_values" ]; then
      echo "$sample_values" | while read -r val; do
        if [ -n "$val" ] && [ "$val" != "null" ]; then
          echo "      Sample: $(echo "$val" | head -c 80)"
        fi
      done
    fi
    echo ""
  done
  
  # Look for epic/parent specifically
  echo "🎯 Key fields for brag docs:"
  epic_field=$(jq -r '.[] | select(.value.name? // .value.displayName? // "" | test("(?i)epic|parent")) | .id' "$all_fields_file" | head -n 1)
  if [ -n "$epic_field" ]; then
    echo "   Epic/Parent field: $epic_field"
  fi
  
  sprint_field=$(jq -r '.[] | select(.type == "array" and (.value[0].name? // "" | test("(?i)sprint"))) | .id' "$all_fields_file" | head -n 1)
  if [ -n "$sprint_field" ]; then
    echo "   Sprint field: $sprint_field"
  fi
fi

# Cleanup
rm -rf "$temp_dir"

echo ""
echo "🎯 Summary:"
echo "   Tickets processed: $processed"
echo "   Successful: $succeeded"
echo "   Failed: $failed"
echo "   Unique custom fields: $field_count"

echo ""
echo "💡 Note: Browser cookies expire. For a permanent solution:"
echo "   1. Regenerate your Jira API token with proper permissions"
echo "   2. Or set up OAuth 2.0 authentication"
