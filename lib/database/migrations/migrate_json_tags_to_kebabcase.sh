#!/bin/bash
# Migrate all JSON files to use kebab-case tags
# Usage: ./migrate_json_tags_to_kebabcase.sh [json_directory]
# Example: ./migrate_json_tags_to_kebabcase.sh ../../../../bragdoc-data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
UTILS_DIR="$PROJECT_ROOT/github-summary/scripts/utils"

# Allow override of target directory
TARGET_DIR="${1:-$PROJECT_ROOT/bragdoc-data}"

# Source normalization utilities
if [ ! -f "$UTILS_DIR/normalize_tags.sh" ]; then
  echo "❌ Error: normalize_tags.sh not found at: $UTILS_DIR/normalize_tags.sh"
  exit 1
fi

source "$UTILS_DIR/normalize_tags.sh"

echo "→ Migrating JSON files to kebab-case tags..."
echo "   Target directory: $TARGET_DIR"

if [ ! -d "$TARGET_DIR" ]; then
  echo "❌ Error: Directory not found: $TARGET_DIR"
  exit 1
fi

migrated=0
skipped=0

for json_file in "$TARGET_DIR"/*.json; do
  if [ ! -f "$json_file" ]; then
    continue
  fi
  
  filename=$(basename "$json_file")
  
  # Skip backup files
  if [[ "$filename" == *.backup ]]; then
    ((skipped++)) || true
    continue
  fi
  
  echo "  Processing $filename..."
  
  # Create backup
  cp "$json_file" "$json_file.backup"
  
  # Use jq to normalize all tags in the file
  jq '[.[] | 
    if .companyGoals then 
      .companyGoals = (.companyGoals | map(
        .tag = (.tag | ascii_downcase | 
          if . == "deliver a positive impact" then "positive-impact"
          elif . == "be bold, collaborate and innovate" then "collaborate-and-innovate"
          elif . == "seek to understand" then "seek-to-understand"
          elif . == "trust and confidentiality" then "trust-and-confidentiality"
          elif . == "embrace differences and empower others" then "embrace-differences-and-empower-others"
          else . end)
      ))
    else . end |
    if .growthAreas then
      .growthAreas = (.growthAreas | map(
        .tag = (.tag | ascii_downcase |
          if . == "goal oriented" then "goal-oriented"
          elif . == "decision making" then "decision-making"
          elif . == "persistence" then "persistence"
          elif . == "personal accountability" then "personal-accountability"
          elif . == "growth mindset" then "growth-mindset"
          elif . == "empathy" then "empathy"
          elif (. == "communication & collaboration" or . == "communication and collaboration") then "communication-and-collaboration"
          elif . == "curiosity" then "curiosity"
          elif . == "customer empathy" then "customer-empathy"
          else . end)
      ))
    else . end
  ]' "$json_file" > "$json_file.tmp"
  
  # Validate the output is valid JSON
  if jq -e . "$json_file.tmp" >/dev/null 2>&1; then
    # Replace original with normalized version
    mv "$json_file.tmp" "$json_file"
    echo "    ✓ Migrated $filename"
    ((migrated++)) || true
  else
    echo "    ✗ Failed to migrate $filename (invalid JSON output)"
    rm "$json_file.tmp"
    # Restore from backup
    mv "$json_file.backup" "$json_file"
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ JSON migration complete"
echo ""
echo "Summary:"
echo "  Migrated: $migrated files"
echo "  Skipped:  $skipped files"
echo ""
echo "Backups saved as *.json.backup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

