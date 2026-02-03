#!/bin/bash
# Migrate company_goals and growth_areas tags to kebab-case format
# Usage: ./migrate_tags_to_kebabcase.sh [--dry-run]
#
# Requires: DATABASE_URL environment variable set
# Example: source .env.local && export DATABASE_URL && ./migrate_tags_to_kebabcase.sh

set -e

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
UTILS_DIR="$PROJECT_ROOT/github-summary/scripts/utils"
POSTGRES_HELPERS="$PROJECT_ROOT/github-summary/scripts/database/postgres_helpers.sh"

# Source utilities
if [ ! -f "$UTILS_DIR/normalize_tags.sh" ]; then
  echo "❌ Error: normalize_tags.sh not found at: $UTILS_DIR/normalize_tags.sh"
  exit 1
fi

source "$UTILS_DIR/normalize_tags.sh"

if [ ! -f "$POSTGRES_HELPERS" ]; then
  echo "❌ Error: postgres_helpers.sh not found at: $POSTGRES_HELPERS"
  exit 1
fi

source "$POSTGRES_HELPERS"

# Parse arguments
DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
  DRY_RUN=true
fi

# Validate DATABASE_URL is set
if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ Error: DATABASE_URL environment variable not set"
  echo ""
  echo "Set it with:"
  echo "  source .env.local && export DATABASE_URL"
  echo ""
  echo "Or directly:"
  echo "  export DATABASE_URL='postgres://username:password@host:port/database'"
  exit 1
fi

# Test connection first
echo "→ Testing database connection..."
if ! pg_test_connection &>/dev/null; then
  echo "❌ Error: Cannot connect to Postgres database"
  echo "   Check your DATABASE_URL"
  exit 1
fi
echo "✅ Connected to database"

# Get total count of records
total_records=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM brag_items;" | xargs)
echo ""
echo "→ Found $total_records total records in brag_items table"

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "🔍 DRY RUN MODE - No changes will be made"
  echo ""
fi

# Fetch all records as JSON array
echo "→ Fetching records from database..."
temp_json=$(mktemp)
trap "rm -f $temp_json" EXIT

psql "$DATABASE_URL" -t -c "
  SELECT json_agg(row_to_json(t))
  FROM (
    SELECT id, company_goals, growth_areas 
    FROM brag_items 
    WHERE company_goals IS NOT NULL OR growth_areas IS NOT NULL
    ORDER BY id
  ) t;
" 2>/dev/null | jq '.' > "$temp_json" 2>/dev/null

if [ ! -s "$temp_json" ] || [ "$(jq '. | length' "$temp_json" 2>/dev/null)" = "null" ]; then
  echo "✅ No records to migrate"
  exit 0
fi

# Process records
updated_count=0
skipped_count=0
error_count=0

echo ""
echo "→ Processing $(jq '. | length' "$temp_json") records..."

# Process each record
jq -c '.[]' "$temp_json" | while read -r record; do
  id=$(echo "$record" | jq -r '.id')
  company_goals=$(echo "$record" | jq -c '.company_goals // null')
  growth_areas=$(echo "$record" | jq -c '.growth_areas // null')
  
  needs_update=false
  new_company_goals="$company_goals"
  new_growth_areas="$growth_areas"
  
  # Normalize company_goals if present
  if [ "$company_goals" != "null" ]; then
    normalized_cg=$(normalize_company_goals_json "$company_goals" 2>/dev/null || echo "")
    if [ -n "$normalized_cg" ] && [ "$normalized_cg" != "$company_goals" ]; then
      new_company_goals="$normalized_cg"
      needs_update=true
    fi
  fi
  
  # Normalize growth_areas if present
  if [ "$growth_areas" != "null" ]; then
    normalized_ga=$(normalize_growth_areas_json "$growth_areas" 2>/dev/null || echo "")
    if [ -n "$normalized_ga" ] && [ "$normalized_ga" != "$growth_areas" ]; then
      new_growth_areas="$normalized_ga"
      needs_update=true
    fi
  fi
  
  if [ "$needs_update" = true ]; then
    if [ "$DRY_RUN" = true ]; then
      echo ""
      echo "  Would update ID $id:"
      if [ "$new_company_goals" != "$company_goals" ]; then
        echo "    Company Goals:"
        echo "      FROM: $company_goals"
        echo "      TO:   $new_company_goals"
      fi
      if [ "$new_growth_areas" != "$growth_areas" ]; then
        echo "    Growth Areas:"
        echo "      FROM: $growth_areas"
        echo "      TO:   $new_growth_areas"
      fi
      ((updated_count++)) || true
    else
      # Escape single quotes for SQL
      new_company_goals_escaped=$(echo "$new_company_goals" | sed "s/'/''/g")
      new_growth_areas_escaped=$(echo "$new_growth_areas" | sed "s/'/''/g")
      
      # Update the record
      update_result=$(psql "$DATABASE_URL" -t -c "
        UPDATE brag_items 
        SET 
          company_goals = '$new_company_goals_escaped'::jsonb,
          growth_areas = '$new_growth_areas_escaped'::jsonb,
          updated_at = NOW()
        WHERE id = $id
        RETURNING id;
      " 2>&1)
      
      if echo "$update_result" | grep -q "$id"; then
        ((updated_count++)) || true
        echo "  ✓ Updated ID $id"
      else
        ((error_count++)) || true
        echo "  ✗ Failed to update ID $id"
      fi
    fi
  else
    ((skipped_count++)) || true
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$DRY_RUN" = true ]; then
  echo "🔍 DRY RUN COMPLETE"
  echo ""
  echo "Summary:"
  echo "  Would update:  $updated_count records"
  echo "  Already OK:    $skipped_count records"
  echo "  Total:         $total_records records"
  echo ""
  echo "To apply changes, run without --dry-run flag"
else
  echo "✅ MIGRATION COMPLETE"
  echo ""
  echo "Summary:"
  echo "  Updated:       $updated_count records"
  echo "  Already OK:    $skipped_count records"
  echo "  Errors:        $error_count records"
  echo "  Total:         $total_records records"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show sample of updated tags
if [ "$updated_count" -gt 0 ] || [ "$DRY_RUN" = false ]; then
  echo ""
  echo "→ Sample of tags in database:"
  psql "$DATABASE_URL" -c "
    SELECT DISTINCT jsonb_array_elements(company_goals)->>'tag' as company_goal_tag 
    FROM brag_items 
    WHERE company_goals IS NOT NULL 
    LIMIT 5;
  " 2>/dev/null || true
  
  psql "$DATABASE_URL" -c "
    SELECT DISTINCT jsonb_array_elements(growth_areas)->>'tag' as growth_area_tag 
    FROM brag_items 
    WHERE growth_areas IS NOT NULL 
    LIMIT 5;
  " 2>/dev/null || true
fi

exit 0
