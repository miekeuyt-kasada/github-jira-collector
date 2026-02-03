#!/bin/bash
# Fix duplicate eventIds in Postgres database
# Run this AFTER fix_duplicate_eventids.sh updates the JSON files
#
# IMPORTANT: This script will:
# 1. Delete the 2 existing manual events (they have wrong hashes)
# 2. Re-persist all 3 manual events from JSON with correct unique hashes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ Error: DATABASE_URL environment variable not set"
  echo "Set it with: source .env.local && export DATABASE_URL"
  exit 1
fi

echo "=== Fixing Manual Events in Database ==="
echo

# Check if psql is available
if ! command -v psql &> /dev/null; then
  echo "❌ Error: psql is not installed"
  exit 1
fi

# Check connection
if ! psql "$DATABASE_URL" -c "SELECT 1" &>/dev/null; then
  echo "❌ Error: Cannot connect to database"
  exit 1
fi

echo "✓ Connected to database"
echo

# Check for the broken commit_shas_hash
echo "Checking for manual events with duplicate hash..."
broken_hash="54b62cd7db3b851c6ad9254ed4b4ce8b9a86625a2133637cae187d462ef543c8"
count=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM brag_items WHERE commit_shas_hash = '$broken_hash'" | tr -d ' ')

if [ "$count" -eq "0" ]; then
  echo "✓ No duplicate hashes found (already fixed or not yet persisted)"
  exit 0
fi

echo "Found $count manual events with duplicate hash (should be 2)"
echo

# Show affected items
echo "Affected items in database:"
psql "$DATABASE_URL" -c "
  SELECT id, month, LEFT(achievement, 60) as achievement, commit_shas_hash
  FROM brag_items 
  WHERE commit_shas_hash = '$broken_hash'
  ORDER BY month, id
"

echo
echo "⚠️  Note: The AI SDK POC event is missing from database (rejected due to duplicate hash)"
echo

# Get the IDs to delete
ids=$(psql "$DATABASE_URL" -t -c "SELECT id FROM brag_items WHERE commit_shas_hash = '$broken_hash' ORDER BY id" | tr '\n' ',' | sed 's/,$//')

echo "Deleting the 2 existing manual events (IDs: $ids)..."
psql "$DATABASE_URL" -c "DELETE FROM brag_items WHERE commit_shas_hash = '$broken_hash'" && echo "✓ Deleted"

echo
echo "Now re-persist all 3 manual events from the fixed JSON files..."
echo

# Check that JSON files have been fixed
echo "Verifying JSON files have been fixed..."
duplicates=$(grep -r "m-eyJhY2hp" "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-{11,12}.json" 2>/dev/null | wc -l | tr -d ' ')

if [ "$duplicates" -gt "0" ]; then
  echo "❌ Error: JSON files still contain duplicate eventIds!"
  echo "   Run ./fix_duplicate_eventids.sh first to fix the JSON files"
  exit 1
fi

echo "✓ JSON files have unique eventIds"
echo

# Re-persist November
echo "Re-persisting November event..."
"$PROJECT_ROOT/steps/05_persist_to_db.sh" 2025-11 2>&1 | grep -E "(Persisted|items|New records)" | head -5

echo
echo "Re-persisting December events..."
"$PROJECT_ROOT/steps/05_persist_to_db.sh" 2025-12 2>&1 | grep -E "(Persisted|items|New records)" | head -5

echo
echo "Verifying all 3 events are now in database..."
manual_count=$(psql "$DATABASE_URL" -t -c "
  SELECT COUNT(*) FROM brag_items 
  WHERE month IN ('2025-11', '2025-12') 
    AND pr_id IS NULL
" | tr -d ' ')

if [ "$manual_count" -eq "3" ]; then
  echo "✅ All 3 manual events successfully in database with unique hashes!"
  echo
  psql "$DATABASE_URL" -c "
    SELECT month, LEFT(achievement, 60) as achievement, 
           LEFT(commit_shas_hash, 16) as hash_prefix
    FROM brag_items 
    WHERE month IN ('2025-11', '2025-12') AND pr_id IS NULL
    ORDER BY month, id
  "
else
  echo "⚠️  Warning: Expected 3 manual events, found $manual_count"
  psql "$DATABASE_URL" -c "
    SELECT month, achievement 
    FROM brag_items 
    WHERE month IN ('2025-11', '2025-12') AND pr_id IS NULL
    ORDER BY month
  "
  exit 1
fi
