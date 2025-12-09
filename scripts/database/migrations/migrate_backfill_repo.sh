#!/bin/bash
# Backfill repo column from github_report.db PR data
# Usage: source .env.local && export DATABASE_URL && ./migrate_backfill_repo.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATABASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$DATABASE_DIR/../.cache"
SQLITE_DB="$CACHE_DIR/github_report.db"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════"
echo "Backfilling repo column from PR cache"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check for psql
if ! command -v psql &> /dev/null; then
  echo -e "${RED}❌ Error: psql is not installed${NC}"
  exit 1
fi

# Check for sqlite3
if ! command -v sqlite3 &> /dev/null; then
  echo -e "${RED}❌ Error: sqlite3 is not installed${NC}"
  exit 1
fi

# Check for connection string
POSTGRES_URL="${DATABASE_URL:-$POSTGRES_URL}"

if [ -z "$POSTGRES_URL" ]; then
  echo -e "${RED}❌ Error: DATABASE_URL environment variable not set${NC}"
  exit 1
fi

# Check for SQLite cache
if [ ! -f "$SQLITE_DB" ]; then
  echo -e "${YELLOW}⚠️  No github_report.db cache found at: $SQLITE_DB${NC}"
  echo "   Cannot backfill - repo will be populated on next enrichment run"
  exit 0
fi

# Test connection
echo "🔌 Testing database connection..."
if ! psql "$POSTGRES_URL" -c "SELECT 1;" &> /dev/null; then
  echo -e "${RED}❌ Error: Cannot connect to Postgres database${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Connection successful${NC}"
echo ""

# Get items that have pr_id but no repo
echo "🔍 Finding items to backfill..."
items_to_backfill=$(psql "$POSTGRES_URL" -t -c "SELECT COUNT(*) FROM brag_items WHERE pr_id IS NOT NULL AND repo IS NULL" | tr -d ' ')
echo "   Items with pr_id but no repo: $items_to_backfill"

if [ "$items_to_backfill" -eq 0 ]; then
  echo -e "${GREEN}✅ No backfill needed - all items already have repo${NC}"
  exit 0
fi

echo ""
echo "🔄 Backfilling from PR cache..."

# Get PR to repo mapping from SQLite
temp_mapping=$(mktemp)
sqlite3 "$SQLITE_DB" -separator '|' "SELECT pr_number, repo FROM prs" > "$temp_mapping"

updated=0
failed=0

while IFS='|' read -r pr_number repo; do
  if [ -n "$pr_number" ] && [ -n "$repo" ]; then
    # Escape single quotes in repo name
    repo_escaped=$(echo "$repo" | sed "s/'/''/g")
    
    result=$(psql "$POSTGRES_URL" -t -c "UPDATE brag_items SET repo = '$repo_escaped', updated_at = NOW() WHERE pr_id = $pr_number AND repo IS NULL RETURNING id" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$(echo "$result" | tr -d ' \n')" ]; then
      count=$(echo "$result" | grep -c '[0-9]' || echo "0")
      ((updated += count)) || true
    fi
  fi
done < "$temp_mapping"

rm -f "$temp_mapping"

# Check remaining
remaining=$(psql "$POSTGRES_URL" -t -c "SELECT COUNT(*) FROM brag_items WHERE pr_id IS NOT NULL AND repo IS NULL" | tr -d ' ')

echo ""
echo -e "${GREEN}✅ Backfill complete!${NC}"
echo "   Updated: $updated items"
echo "   Remaining without repo: $remaining"
echo ""
echo "════════════════════════════════════════════════════════════════"


