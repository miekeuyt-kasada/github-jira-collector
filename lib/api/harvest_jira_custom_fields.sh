#!/bin/bash
# Harvest all custom fields from Jira issues referenced in github_data.db
# Usage: ./harvest_jira_custom_fields.sh [path/to/github_data.db] [limit]
#   limit: optional, number of issues to sample (default: all)

set -euo pipefail

# Check required environment variables
if [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_BASE_URL:-}" ]; then
  echo "❌ Error: Required environment variables not set"
  echo ""
  echo "Please set the following in .env.local:"
  echo "  JIRA_EMAIL=your-email@kasada.io"
  echo "  JIRA_API_TOKEN=your-api-token"
  echo "  JIRA_BASE_URL=https://kasada.atlassian.net"
  echo ""
  echo "Then run: source .env.local && export JIRA_EMAIL JIRA_API_TOKEN JIRA_BASE_URL"
  exit 1
fi

# Get database path and optional limit
DB_PATH="${1:-github-summary/.cache/github_data.db}"
LIMIT="${2:-0}"

if [ ! -f "$DB_PATH" ]; then
  echo "❌ Error: Database not found at $DB_PATH"
  exit 1
fi

if [ "$LIMIT" -gt 0 ]; then
  echo "⚠️  Testing mode: will sample first $LIMIT issues only"
  echo ""
fi

echo "🔍 Harvesting custom fields from Jira issues..."
echo ""

# Create auth header
AUTH_HEADER="Authorization: Basic $(echo -n "$JIRA_EMAIL:$JIRA_API_TOKEN" | base64)"

# Get all unique Jira tickets from the database
echo "📊 Querying database for Jira tickets..."
jira_tickets=$(sqlite3 "$DB_PATH" "SELECT DISTINCT jira_ticket FROM prs WHERE jira_ticket IS NOT NULL AND jira_ticket != '' ORDER BY jira_ticket;" 2>/dev/null || echo "")

if [ -z "$jira_tickets" ]; then
  echo "❌ No Jira tickets found in database"
  exit 1
fi

ticket_count=$(echo "$jira_tickets" | wc -l | tr -d ' ')
echo "   Found $ticket_count unique Jira tickets"
echo ""

# Create temporary files for collecting custom fields
temp_dir=$(mktemp -d)
all_fields_file="$temp_dir/all_fields.json"
echo "[]" > "$all_fields_file"

echo "🌐 Fetching issue details from Jira..."
processed=0
failed=0

echo "$jira_tickets" | while read -r ticket; do
  if [ -z "$ticket" ]; then
    continue
  fi
  
  processed=$((processed + 1))
  
  # Check limit
  if [ "$LIMIT" -gt 0 ] && [ "$processed" -gt "$LIMIT" ]; then
    break
  fi
  echo -n "   [$processed/$ticket_count] $ticket ... "
  
  # Fetch issue from Jira
  response=$(curl -s -X GET \
    "$JIRA_BASE_URL/rest/api/3/issue/$ticket" \
    -H "Accept: application/json" \
    -H "$AUTH_HEADER" 2>/dev/null || echo '{"error": true}')
  
  # Check for errors
  if echo "$response" | jq -e '.errorMessages' > /dev/null 2>&1; then
    error_msg=$(echo "$response" | jq -r '.errorMessages[0]' 2>/dev/null | head -c 60)
    echo "❌ $error_msg"
    failed=$((failed + 1))
    continue
  fi
  
  if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed"
    failed=$((failed + 1))
    continue
  fi
  
  # Check if we got valid data
  if ! echo "$response" | jq -e '.fields' > /dev/null 2>&1; then
    echo "❌ No fields in response"
    failed=$((failed + 1))
    continue
  fi
  
  # Extract custom field IDs and their values
  custom_fields=$(echo "$response" | jq -r '.fields | to_entries[] | select(.key | startswith("customfield_")) | {id: .key, value: .value, type: (.value | type)}' 2>/dev/null || echo "")
  
  if [ -n "$custom_fields" ]; then
    # Append to our collection
    echo "$custom_fields" | jq -s '.' >> "$temp_dir/fields_$ticket.json"
    echo "✅"
  else
    echo "⚠️  No custom fields"
  fi
  
  # Rate limiting - be nice to the API
  sleep 0.5
done

echo ""
echo "📦 Aggregating and deduplicating fields..."

# Combine all field files
cat "$temp_dir"/fields_*.json 2>/dev/null | jq -s 'add | unique_by(.id)' > "$all_fields_file" 2>/dev/null || echo "[]" > "$all_fields_file"

# Fetch field metadata to get names
echo "📋 Fetching field metadata..."
metadata_response=$(curl -s -X GET \
  "$JIRA_BASE_URL/rest/api/3/field" \
  -H "Accept: application/json" \
  -H "$AUTH_HEADER")

echo ""
echo "✅ Custom fields discovered:"
echo ""

# Display results with metadata
field_count=$(jq -r 'length' "$all_fields_file")
if [ "$field_count" -eq 0 ]; then
  echo "   No custom fields found"
else
  jq -r '.[] | .id' "$all_fields_file" | sort | while read -r field_id; do
    # Get field name from metadata
    field_name=$(echo "$metadata_response" | jq -r ".[] | select(.id == \"$field_id\") | .name" 2>/dev/null || echo "Unknown")
    
    # Get a sample non-null value
    sample_value=$(jq -r ".[] | select(.id == \"$field_id\" and .value != null) | .value | if type == \"object\" then .name // .value // \"[object]\" elif type == \"array\" then (.[0].name // .[0].value // \"[array]\") else . end" "$all_fields_file" 2>/dev/null | head -n 1 | head -c 80)
    
    echo "   $field_id"
    echo "      Name: $field_name"
    if [ -n "$sample_value" ] && [ "$sample_value" != "null" ]; then
      echo "      Sample: $sample_value"
    fi
    echo ""
  done
fi

# Cleanup
rm -rf "$temp_dir"

echo ""
echo "🎯 Summary:"
echo "   Tickets processed: $processed"
echo "   Unique custom fields: $field_count"
if [ "$failed" -gt 0 ]; then
  echo "   Failed requests: $failed"
fi

echo ""
echo "💡 Next steps:"
echo "   Add relevant fields to your .env.local, e.g.:"
echo "   JIRA_EPIC_FIELD=customfield_10014"
echo "   JIRA_SPRINT_FIELD=customfield_10020"
