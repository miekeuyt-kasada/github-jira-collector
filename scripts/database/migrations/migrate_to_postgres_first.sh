#!/bin/bash
# Migrate to Postgres-first architecture with native arrays and hash-based deduplication
# Usage: ./migrate_to_postgres_first.sh
#
# This migration:
# 1. Creates the new schema with native Postgres arrays
# 2. Adds commit_shas_hash column for deduplication
# 3. Migrates existing data from SQLite
# 4. Computes hashes for existing records

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATABASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$DATABASE_DIR/../.cache"
SQLITE_DB="$CACHE_DIR/bragdoc_items.db"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════"
echo "Migrating to Postgres-first architecture"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check for psql
if ! command -v psql &> /dev/null; then
  echo -e "${RED}❌ Error: psql is not installed${NC}"
  echo "Install via: brew install postgresql (macOS) or apt-get install postgresql-client (Linux)"
  exit 1
fi

# Check for connection string
POSTGRES_URL="${DATABASE_URL:-$POSTGRES_URL}"

if [ -z "$POSTGRES_URL" ]; then
  echo -e "${RED}❌ Error: DATABASE_URL environment variable not set${NC}"
  echo ""
  echo "Set it with: export DATABASE_URL='postgres://...'"
  echo "Or: source .env.local && export DATABASE_URL"
  exit 1
fi

# Test connection
echo "🔌 Testing database connection..."
if ! psql "$POSTGRES_URL" -c "SELECT 1;" &> /dev/null; then
  echo -e "${RED}❌ Error: Cannot connect to Postgres database${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Connection successful${NC}"
echo ""

# Step 1: Create/update schema with new columns
echo "📋 Step 1: Creating new schema..."
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 <<'EOF'
-- Create table if not exists (with new schema)
CREATE TABLE IF NOT EXISTS brag_items (
  id SERIAL PRIMARY KEY,
  achievement TEXT NOT NULL,
  dates DATE[],
  company_goals JSONB,
  growth_areas JSONB,
  outcomes TEXT,
  impact TEXT,
  pr_id INTEGER,
  ticket_no TEXT,
  commit_shas TEXT[],
  commit_shas_hash TEXT,
  state TEXT,
  month TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add new columns if they don't exist (for existing tables)
DO $$
BEGIN
  -- Add commit_shas_hash if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'brag_items' AND column_name = 'commit_shas_hash'
  ) THEN
    ALTER TABLE brag_items ADD COLUMN commit_shas_hash TEXT;
  END IF;

  -- Convert dates from JSONB to DATE[] if needed
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'brag_items' AND column_name = 'dates' AND data_type = 'jsonb'
  ) THEN
    -- Clean up any partial migration state
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'brag_items' AND column_name = 'dates_new'
    ) THEN
      ALTER TABLE brag_items DROP COLUMN dates_new;
    END IF;
    
    -- Add temporary column
    ALTER TABLE brag_items ADD COLUMN dates_new DATE[];
    
    -- Migrate double-encoded strings (most common case)
    UPDATE brag_items 
    SET dates_new = (
      SELECT array_agg(elem::DATE)
      FROM jsonb_array_elements_text((dates #>> '{}')::jsonb) AS elem
    )
    WHERE jsonb_typeof(dates) = 'string' 
      AND (dates #>> '{}') LIKE '[%';
    
    -- Migrate actual JSONB arrays
    UPDATE brag_items 
    SET dates_new = (
      SELECT array_agg(elem::DATE)
      FROM jsonb_array_elements_text(dates) AS elem
    )
    WHERE jsonb_typeof(dates) = 'array'
      AND dates_new IS NULL;
    
    -- Migrate plain string dates
    UPDATE brag_items 
    SET dates_new = ARRAY[(dates #>> '{}')::DATE]
    WHERE jsonb_typeof(dates) = 'string' 
      AND (dates #>> '{}') NOT LIKE '[%'
      AND dates_new IS NULL;
    
    -- Drop old column and rename
    ALTER TABLE brag_items DROP COLUMN dates;
    ALTER TABLE brag_items RENAME COLUMN dates_new TO dates;
  END IF;

  -- Convert commit_shas from JSONB to TEXT[] if needed
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'brag_items' AND column_name = 'commit_shas' AND data_type = 'jsonb'
  ) THEN
    -- Clean up any partial migration state
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'brag_items' AND column_name = 'commit_shas_new'
    ) THEN
      ALTER TABLE brag_items DROP COLUMN commit_shas_new;
    END IF;
    
    -- Add temporary column
    ALTER TABLE brag_items ADD COLUMN commit_shas_new TEXT[];
    
    -- Migrate double-encoded strings (most common case)
    UPDATE brag_items 
    SET commit_shas_new = (
      SELECT array_agg(elem)
      FROM jsonb_array_elements_text((commit_shas #>> '{}')::jsonb) AS elem
    )
    WHERE jsonb_typeof(commit_shas) = 'string' 
      AND (commit_shas #>> '{}') LIKE '[%';
    
    -- Migrate actual JSONB arrays
    UPDATE brag_items 
    SET commit_shas_new = (
      SELECT array_agg(elem)
      FROM jsonb_array_elements_text(commit_shas) AS elem
    )
    WHERE jsonb_typeof(commit_shas) = 'array'
      AND commit_shas_new IS NULL;
    
    -- Migrate plain string SHAs
    UPDATE brag_items 
    SET commit_shas_new = ARRAY[commit_shas #>> '{}']
    WHERE jsonb_typeof(commit_shas) = 'string' 
      AND (commit_shas #>> '{}') NOT LIKE '[%'
      AND commit_shas_new IS NULL;
    
    -- Drop old column and rename
    ALTER TABLE brag_items DROP COLUMN commit_shas;
    ALTER TABLE brag_items RENAME COLUMN commit_shas_new TO commit_shas;
  END IF;
END $$;

-- Compute commit_shas_hash for existing records that don't have one
UPDATE brag_items 
SET commit_shas_hash = encode(
  sha256(
    (SELECT string_agg(s, ',' ORDER BY s) FROM unnest(commit_shas) AS s)::bytea
  ), 
  'hex'
)
WHERE commit_shas_hash IS NULL 
  AND commit_shas IS NOT NULL 
  AND array_length(commit_shas, 1) > 0;

-- Fallback hash for items without commits (use pr_id or ticket_no or achievement)
UPDATE brag_items 
SET commit_shas_hash = encode(
  sha256(
    COALESCE(
      pr_id::TEXT,
      ticket_no,
      LEFT(achievement, 100)
    )::bytea
  ),
  'hex'
)
WHERE commit_shas_hash IS NULL;

-- Now make commit_shas_hash NOT NULL
ALTER TABLE brag_items ALTER COLUMN commit_shas_hash SET NOT NULL;

-- Drop old unique indexes that might conflict
DROP INDEX IF EXISTS idx_brag_items_pr_month;
DROP INDEX IF EXISTS idx_brag_items_ticket_month;

-- Create the new deduplication index
CREATE UNIQUE INDEX IF NOT EXISTS idx_brag_items_dedupe 
  ON brag_items(commit_shas_hash, month);

-- Query indexes
CREATE INDEX IF NOT EXISTS idx_brag_items_month ON brag_items(month);
CREATE INDEX IF NOT EXISTS idx_brag_items_pr_id ON brag_items(pr_id);
CREATE INDEX IF NOT EXISTS idx_brag_items_state ON brag_items(state);
EOF

echo -e "${GREEN}✅ Schema updated${NC}"
echo ""

# Step 2: Migrate data from SQLite if it exists and has data not in Postgres
if [ -f "$SQLITE_DB" ]; then
  echo "📦 Step 2: Checking for SQLite data to migrate..."
  
  sqlite_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM brag_items" 2>/dev/null || echo "0")
  postgres_count=$(psql "$POSTGRES_URL" -t -c "SELECT COUNT(*) FROM brag_items" 2>/dev/null | tr -d ' ')
  
  echo "  SQLite items: $sqlite_count"
  echo "  Postgres items: $postgres_count"
  
  if [ "$sqlite_count" -gt 0 ] && [ "$postgres_count" -eq 0 ]; then
    echo ""
    echo "🔄 Migrating SQLite data to Postgres..."
    
    # Export from SQLite and import to Postgres
    temp_file=$(mktemp)
    sqlite3 "$SQLITE_DB" -json "SELECT * FROM brag_items ORDER BY id" > "$temp_file"
    
    migrated=0
    failed=0
    
    while IFS= read -r item; do
      achievement=$(echo "$item" | jq -r '.achievement // ""' | sed "s/'/''/g")
      
      # Parse dates - SQLite stores as JSON string
      dates_json=$(echo "$item" | jq -c '.dates // "[]"')
      if [ "$dates_json" = "null" ] || [ "$dates_json" = '""' ]; then
        dates_sql="NULL"
      else
        # Convert JSON array to Postgres array literal
        dates_array=$(echo "$dates_json" | jq -r 'if type == "string" then fromjson? // [] else . end | map(.) | join(",")')
        if [ -z "$dates_array" ]; then
          dates_sql="NULL"
        else
          dates_sql="ARRAY[$(echo "$dates_array" | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/" )]::DATE[]"
        fi
      fi
      
      company_goals=$(echo "$item" | jq -c '.company_goals // "[]"' | sed "s/'/''/g")
      growth_areas=$(echo "$item" | jq -c '.growth_areas // "[]"' | sed "s/'/''/g")
      outcomes=$(echo "$item" | jq -r '.outcomes // ""' | sed "s/'/''/g")
      impact=$(echo "$item" | jq -r '.impact // ""' | sed "s/'/''/g")
      pr_id=$(echo "$item" | jq -r '.pr_id // "null"')
      ticket_no=$(echo "$item" | jq -r '.ticket_no // "null"')
      
      # Parse commit_shas
      commit_shas_json=$(echo "$item" | jq -c '.commit_shas // "[]"')
      if [ "$commit_shas_json" = "null" ] || [ "$commit_shas_json" = '""' ] || [ "$commit_shas_json" = "[]" ]; then
        commit_shas_sql="NULL"
        # Compute fallback hash
        hash_input="${pr_id:-${ticket_no:-${achievement:0:100}}}"
        commit_shas_hash=$(echo -n "$hash_input" | shasum -a 256 | cut -d' ' -f1)
      else
        # Convert JSON array to Postgres array
        commit_shas_array=$(echo "$commit_shas_json" | jq -r 'if type == "string" then fromjson? // [] else . end | sort | .[]' | tr '\n' ',' | sed 's/,$//')
        if [ -z "$commit_shas_array" ]; then
          commit_shas_sql="NULL"
          hash_input="${pr_id:-${ticket_no:-${achievement:0:100}}}"
          commit_shas_hash=$(echo -n "$hash_input" | shasum -a 256 | cut -d' ' -f1)
        else
          commit_shas_sql="ARRAY[$(echo "$commit_shas_array" | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/")]::TEXT[]"
          # Compute hash from sorted shas
          sorted_shas=$(echo "$commit_shas_json" | jq -r 'if type == "string" then fromjson? // [] else . end | sort | join(",")')
          commit_shas_hash=$(echo -n "$sorted_shas" | shasum -a 256 | cut -d' ' -f1)
        fi
      fi
      
      state=$(echo "$item" | jq -r '.state // "null"')
      month=$(echo "$item" | jq -r '.month // ""')
      created_at=$(echo "$item" | jq -r '.created_at // ""')
      updated_at=$(echo "$item" | jq -r '.updated_at // ""')
      
      # Build and execute INSERT
      sql="INSERT INTO brag_items (
        achievement, dates, company_goals, growth_areas, outcomes, impact,
        pr_id, ticket_no, commit_shas, commit_shas_hash, state, month, created_at, updated_at
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
        '$month',
        '$created_at'::timestamptz,
        '$updated_at'::timestamptz
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
        updated_at = EXCLUDED.updated_at;"
      
      if psql "$POSTGRES_URL" -c "$sql" &>/dev/null; then
        ((migrated++)) || true
      else
        ((failed++)) || true
        echo -e "${YELLOW}⚠️  Failed to migrate: ${achievement:0:50}...${NC}"
      fi
    done < <(jq -c '.[]' "$temp_file")
    
    rm -f "$temp_file"
    
    echo ""
    echo "  Migrated: $migrated"
    echo "  Failed: $failed"
  else
    echo -e "${GREEN}✅ No migration needed (Postgres already has data or SQLite is empty)${NC}"
  fi
else
  echo "📦 Step 2: No SQLite database found, skipping migration"
fi

echo ""

# Step 3: Verify
echo "🔍 Step 3: Verifying migration..."
final_count=$(psql "$POSTGRES_URL" -t -c "SELECT COUNT(*) FROM brag_items" | tr -d ' ')
echo "  Total items in Postgres: $final_count"

# Show schema
echo ""
echo "📊 Current schema:"
psql "$POSTGRES_URL" -c "\d brag_items" 2>/dev/null | head -30

echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Migration complete!${NC}"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Test with: ./steps/05_persist_to_db.sh 2025-11"
echo "  2. Archive old scripts: rename bragdoc_db_*.sh to old_bragdoc_db_*.sh"
echo "  3. Archive sync script: rename sync_to_postgres.sh to old_sync_to_postgres.sh"
echo ""

