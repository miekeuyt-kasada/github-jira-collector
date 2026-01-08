#!/bin/bash
# Fix duplicate eventIds caused by broken base64 approach
# Regenerates unique SHA-256 based IDs for affected manual events

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo "=== Fixing Duplicate EventIds ==="
echo
echo "This script will fix 3 manual events that have the same broken eventId: m-eyJhY2hp"
echo

# Backup files first
echo "Creating backups..."
cp "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-11.json" "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-11.json.backup"
cp "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json" "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json.backup"

echo "✓ Backups created"
echo

# Fix November 2025 - Won Android SDK bug bash
echo "Fixing November 2025: Won Android SDK bug bash"
jq '
  map(
    if .eventId? == "m-eyJhY2hp" and (.achievement | contains("Android SDK bug bash")) then
      .eventId = "m-8aa64acc"
    else
      .
    end
  )
' "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-11.json" > "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-11.json.tmp"
mv "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-11.json.tmp" "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-11.json"

echo "✓ Fixed November event"

# Fix December 2025 - AI SDK POC
echo "Fixing December 2025: Built AI SDK proof-of-concept"
jq '
  map(
    if .eventId? == "m-eyJhY2hp" and (.achievement | contains("AI SDK proof-of-concept")) then
      .eventId = "m-1099c692"
    else
      .
    end
  )
' "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json" > "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json.tmp"
mv "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json.tmp" "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json"

echo "✓ Fixed December event 1"

# Fix December 2025 - Tab Overlay
echo "Fixing December 2025: Built Tab Overlay Compare Chrome extension"
jq '
  map(
    if .eventId? == "m-eyJhY2hp" and (.achievement | contains("Tab Overlay Compare")) then
      .eventId = "m-ff4fb335"
    else
      .
    end
  )
' "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json" > "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json.tmp"
mv "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json.tmp" "$PROJECT_ROOT/bragdoc-data/bragdoc-data-2025-12.json"

echo "✓ Fixed December event 2"
echo

# Verify no duplicates remain
echo "Verifying fix..."
duplicates=$(grep -r "m-eyJhY2hp" "$PROJECT_ROOT/bragdoc-data"/*.json 2>/dev/null | wc -l | tr -d ' ')

if [ "$duplicates" -eq "0" ]; then
  echo "✅ All duplicate IDs fixed!"
  echo
  echo "New unique IDs:"
  echo "  - November: m-8aa64acc (Won Android SDK bug bash)"
  echo "  - December: m-1099c692 (Built AI SDK POC)"
  echo "  - December: m-ff4fb335 (Built Tab Overlay Compare)"
  echo
  echo "Backups saved as:"
  echo "  - bragdoc-data/bragdoc-data-2025-11.json.backup"
  echo "  - bragdoc-data/bragdoc-data-2025-12.json.backup"
else
  echo "⚠️  Warning: Found $duplicates remaining instances of m-eyJhY2hp"
  grep -r "m-eyJhY2hp" "$PROJECT_ROOT/bragdoc-data"/*.json 2>/dev/null
  exit 1
fi

echo
echo "Next step: If you use Postgres, run the migration to update the database:"
echo "  ./fix_duplicate_eventids_db.sh"
