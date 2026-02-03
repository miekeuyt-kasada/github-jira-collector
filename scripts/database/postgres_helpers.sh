#!/bin/bash
# Helper functions for Postgres-first brag doc database operations
# These functions replace bragdoc_db_helpers.sh for direct Postgres access

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get connection URL
get_postgres_url() {
  local url="${DATABASE_URL:-$POSTGRES_URL}"
  if [ -z "$url" ]; then
    echo -e "${RED}❌ Error: DATABASE_URL environment variable not set${NC}" >&2
    echo "Set it with: export DATABASE_URL='postgres://...'" >&2
    echo "Or: source .env.local && export DATABASE_URL" >&2
    return 1
  fi
  echo "$url"
}

# Validate psql is available
check_psql() {
  if ! command -v psql &> /dev/null; then
    echo -e "${RED}❌ Error: psql is not installed${NC}" >&2
    echo "Install via: brew install postgresql (macOS)" >&2
    return 1
  fi
}

# Compute deterministic hash from commit SHAs (or fallback identifiers)
# Args: commit_shas_json, pr_id (optional), ticket_no (optional), event_id (optional), achievement (optional)
# Fallback order: commitShas → prId → ticketNo → eventId → achievement
compute_shas_hash() {
  local commit_shas_json="$1"
  local pr_id="$2"
  local ticket_no="$3"
  local event_id="$4"
  local achievement="$5"
  
  # If we have commit_shas, use them
  if [ -n "$commit_shas_json" ] && [ "$commit_shas_json" != "null" ] && [ "$commit_shas_json" != "[]" ]; then
    # Sort and join shas, then hash
    local sorted_shas
    sorted_shas=$(echo "$commit_shas_json" | jq -r 'if type == "string" then fromjson? // [] else . end | sort | join(",")')
    if [ -n "$sorted_shas" ]; then
      echo -n "$sorted_shas" | shasum -a 256 | cut -d' ' -f1
      return
    fi
  fi
  
  # Fallback: use pr_id, ticket_no, event_id, or achievement (in that order)
  local hash_input=""
  if [ -n "$pr_id" ] && [ "$pr_id" != "null" ]; then
    hash_input="$pr_id"
  elif [ -n "$ticket_no" ] && [ "$ticket_no" != "null" ]; then
    hash_input="$ticket_no"
  elif [ -n "$event_id" ] && [ "$event_id" != "null" ]; then
    hash_input="$event_id"
  elif [ -n "$achievement" ]; then
    hash_input="${achievement:0:100}"
  fi
  
  if [ -z "$hash_input" ]; then
    hash_input="unknown-$(date +%s)-$RANDOM"
  fi
  echo -n "$hash_input" | shasum -a 256 | cut -d' ' -f1
}

# Convert JSON array to Postgres TEXT[] literal
# Args: json_array
json_to_text_array() {
  local json="$1"
  
  if [ -z "$json" ] || [ "$json" = "null" ] || [ "$json" = "[]" ]; then
    echo "NULL"
    return
  fi
  
  # Use jq to build comma-separated quoted elements
  local elements
  elements=$(echo "$json" | jq -r '
    if type == "string" then fromjson? // [] else . end 
    | if length == 0 then "" 
      else map(@json) | join(",") 
      end
  ' 2>/dev/null)
  
  if [ -z "$elements" ]; then
    echo "NULL"
  else
    # Convert JSON strings to SQL strings (double quotes to single quotes)
    elements=$(echo "$elements" | sed "s/\"/'/g")
    echo "ARRAY[$elements]::TEXT[]"
  fi
}

# Convert JSON array of date strings to Postgres DATE[] literal
# Args: json_array
json_to_date_array() {
  local json="$1"
  
  if [ -z "$json" ] || [ "$json" = "null" ] || [ "$json" = "[]" ]; then
    echo "NULL"
    return
  fi
  
  # Use jq to build comma-separated quoted dates
  local elements
  elements=$(echo "$json" | jq -r '
    if type == "string" then fromjson? // [] else . end 
    | if length == 0 then "" 
      else map("'"'"'" + . + "'"'"'") | join(",") 
      end
  ' 2>/dev/null)
  
  if [ -z "$elements" ]; then
    echo "NULL"
  else
    echo "ARRAY[$elements]::DATE[]"
  fi
}

# Insert or update a brag item in Postgres
# Args: JSON string of a single brag item, month (YYYY-MM)
# Returns: inserted/updated id or error
pg_insert_brag_item() {
  local item_json="$1"
  local month="$2"
  
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  # Extract fields from JSON
  local achievement=$(echo "$item_json" | jq -r '.achievement // ""' | sed "s/'/''/g")
  local dates_json=$(echo "$item_json" | jq -c '.dates // []')
  local company_goals=$(echo "$item_json" | jq -c '.companyGoals // []' | sed "s/'/''/g")
  local growth_areas=$(echo "$item_json" | jq -c '.growthAreas // []' | sed "s/'/''/g")
  local outcomes=$(echo "$item_json" | jq -r '.outcomes // ""' | sed "s/'/''/g")
  local impact=$(echo "$item_json" | jq -r '.impact // ""' | sed "s/'/''/g")
  local pr_id=$(echo "$item_json" | jq -r '.prId // "null"')
  local ticket_no=$(echo "$item_json" | jq -r '.ticketNo // "null"')
  local event_id=$(echo "$item_json" | jq -r '.eventId // "null"')
  local commit_shas_json=$(echo "$item_json" | jq -c '.commitShas // []')
  local state=$(echo "$item_json" | jq -r '.state // "null"')
  local repo=$(echo "$item_json" | jq -r '.repo // "null"')
  local epic_key=$(echo "$item_json" | jq -r '.epicKey // "null"')
  local epic_name=$(echo "$item_json" | jq -r '.epicName // "null"' | sed "s/'/''/g")
  local effort_score=$(echo "$item_json" | jq -r '.effortScore // "null"')
  
  # Compute hash for deduplication
  local commit_shas_hash
  commit_shas_hash=$(compute_shas_hash "$commit_shas_json" "$pr_id" "$ticket_no" "$event_id" "$achievement")
  
  # Convert arrays to Postgres format
  local dates_sql=$(json_to_date_array "$dates_json")
  local commit_shas_sql=$(json_to_text_array "$commit_shas_json")
  
  # Build SQL
  local sql="INSERT INTO brag_items (
    achievement, dates, company_goals, growth_areas, outcomes, impact,
    pr_id, ticket_no, commit_shas, commit_shas_hash, state, repo, month,
    epic_key, epic_name, effort_score,
    created_at, updated_at
  ) VALUES (
    '$achievement',
    $dates_sql,
    '$company_goals'::jsonb,
    '$growth_areas'::jsonb,
    '$outcomes',
    '$impact',
    $([ "$pr_id" = "null" ] && echo "NULL" || echo "$pr_id"),
    $([ "$ticket_no" = "null" ] && echo "NULL" || echo "'$ticket_no'"),
    $commit_shas_sql,
    '$commit_shas_hash',
    $([ "$state" = "null" ] && echo "NULL" || echo "'$state'"),
    $([ "$repo" = "null" ] && echo "NULL" || echo "'$repo'"),
    '$month',
    $([ "$epic_key" = "null" ] && echo "NULL" || echo "'$epic_key'"),
    $([ "$epic_name" = "null" ] && echo "NULL" || echo "'$epic_name'"),
    $([ "$effort_score" = "null" ] && echo "NULL" || echo "$effort_score"),
    NOW(),
    NOW()
  )
  ON CONFLICT (commit_shas_hash, month) DO UPDATE SET
    achievement = EXCLUDED.achievement,
    dates = EXCLUDED.dates,
    company_goals = EXCLUDED.company_goals,
    growth_areas = EXCLUDED.growth_areas,
    outcomes = EXCLUDED.outcomes,
    impact = EXCLUDED.impact,
    pr_id = EXCLUDED.pr_id,
    ticket_no = EXCLUDED.ticket_no,
    commit_shas = EXCLUDED.commit_shas,
    state = EXCLUDED.state,
    repo = COALESCE(EXCLUDED.repo, brag_items.repo),
    epic_key = EXCLUDED.epic_key,
    epic_name = EXCLUDED.epic_name,
    effort_score = EXCLUDED.effort_score,
    updated_at = NOW()
  RETURNING id;"
  
  # Execute
  local result
  result=$(psql "$pg_url" -t -c "$sql" 2>&1)
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    # Extract just the ID (remove whitespace and any extra psql output)
    echo "$result" | tr -d ' \n' | grep -oE '^[0-9]+'
  else
    echo -e "${RED}❌ Insert failed: $result${NC}" >&2
    return 1
  fi
}

# Get all items for a specific month
# Args: month (YYYY-MM)
pg_get_items_for_month() {
  local month="$1"
  
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  psql "$pg_url" -t -A -c "
    SELECT json_agg(row_to_json(t))
    FROM (
      SELECT 
        id,
        achievement,
        dates,
        company_goals as \"companyGoals\",
        growth_areas as \"growthAreas\",
        outcomes,
        impact,
        pr_id as \"prId\",
        ticket_no as \"ticketNo\",
        commit_shas as \"commitShas\",
        commit_shas_hash as \"commitShasHash\",
        state,
        repo,
        month,
        created_at as \"createdAt\",
        updated_at as \"updatedAt\"
      FROM brag_items 
      WHERE month = '$month'
      ORDER BY id
    ) t
  " 2>/dev/null | jq '.' 2>/dev/null || echo "[]"
}

# Get an item by PR ID
# Args: pr_id
pg_get_item_by_pr() {
  local pr_id="$1"
  
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  psql "$pg_url" -t -A -c "
    SELECT row_to_json(t)
    FROM (
      SELECT * FROM brag_items WHERE pr_id = $pr_id LIMIT 1
    ) t
  " 2>/dev/null
}

# Get count of items for a specific month
# Args: month (YYYY-MM)
pg_get_month_item_count() {
  local month="$1"
  
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  psql "$pg_url" -t -c "SELECT COUNT(*) FROM brag_items WHERE month = '$month'" 2>/dev/null | tr -d ' '
}

# Get total count of items
pg_get_item_count() {
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  psql "$pg_url" -t -c "SELECT COUNT(*) FROM brag_items" 2>/dev/null | tr -d ' '
}

# Get all distinct months that have items
pg_get_all_months() {
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  psql "$pg_url" -t -A -c "SELECT DISTINCT month FROM brag_items ORDER BY month" 2>/dev/null
}

# Export month data to JSON file
# Args: month (YYYY-MM), output_file
pg_export_month_to_json() {
  local month="$1"
  local output_file="$2"
  
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  psql "$pg_url" -t -A -c "
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json)
    FROM (
      SELECT 
        achievement,
        dates,
        company_goals as \"companyGoals\",
        growth_areas as \"growthAreas\",
        outcomes,
        impact,
        pr_id as \"prId\",
        ticket_no as \"ticketNo\",
        commit_shas as \"commitShas\",
        state,
        repo,
        month
      FROM brag_items 
      WHERE month = '$month'
      ORDER BY id
    ) t
  " 2>/dev/null | jq '.' > "$output_file"
  
  echo "✅ Exported month $month to: $output_file"
}

# Test database connection
pg_test_connection() {
  check_psql || return 1
  local pg_url
  pg_url=$(get_postgres_url) || return 1
  
  if psql "$pg_url" -c "SELECT 1;" &>/dev/null; then
    echo -e "${GREEN}✅ Database connection successful${NC}"
    return 0
  else
    echo -e "${RED}❌ Cannot connect to database${NC}"
    return 1
  fi
}

