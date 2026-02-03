#!/bin/bash
# Generate markdown report from cached GitHub data
# Usage: ./generate_report.sh <username> <start_date> <end_date> [output_file]
# Examples:
#   ./generate_report.sh miekeuyt 2025-07-01 2025-10-01
#   ./generate_report.sh miekeuyt 2025-07-01 2025-10-01 custom-report.md

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/database/db_helpers.sh"

USERNAME="${1:-}"
DATE_START="${2:-}"
DATE_END="${3:-}"
OUTPUT_FILE="${4:-$SCRIPT_DIR/../generated/$USERNAME-commits-${DATE_START}_${DATE_END}.md}"

if [ -z "$USERNAME" ] || [ -z "$DATE_START" ] || [ -z "$DATE_END" ]; then
  echo "Usage: $0 <username> <start_date> <end_date> [output_file]"
  echo "Example: $0 miekeuyt 2025-07-01 2025-10-01"
  exit 1
fi

# Check database exists
DB_PATH="$SCRIPT_DIR/.cache/github_data.db"
if [ ! -f "$DB_PATH" ]; then
  echo "❌ Error: Database not found at $DB_PATH"
  echo "   Run ./get_github_data.sh first to fetch and cache data"
  exit 1
fi

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUTPUT_DIR"

echo "Generating report from database cache..."

# Write report header
echo "# GitHub Commits by $USERNAME" > "$OUTPUT_FILE"
echo "## Period: $DATE_START to $DATE_END" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Get unique repos in date range
REPOS=$(sqlite3 "$DB_PATH" <<SQL
SELECT DISTINCT repo FROM (
  SELECT repo FROM prs 
  WHERE created_at >= '$DATE_START' AND created_at < '$DATE_END'
  UNION
  SELECT repo FROM direct_commits 
  WHERE date >= '$DATE_START' AND date < '$DATE_END'
)
ORDER BY repo;
SQL
)

if [ -z "$REPOS" ]; then
  echo "No data found in database for date range $DATE_START to $DATE_END"
  echo "" >> "$OUTPUT_FILE"
  echo "_No activity found in this period._" >> "$OUTPUT_FILE"
  echo "✅ Report generated: $OUTPUT_FILE"
  exit 0
fi

# Process each repo
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  
  echo "  Processing $repo..."
  
  # Count PRs
  PR_COUNT=$(sqlite3 "$DB_PATH" <<SQL
SELECT COUNT(*) FROM prs 
WHERE repo='$repo' 
  AND created_at >= '$DATE_START' 
  AND created_at < '$DATE_END';
SQL
)
  
  # Count direct commits
  COMMIT_COUNT=$(sqlite3 "$DB_PATH" <<SQL
SELECT COUNT(*) FROM direct_commits 
WHERE repo='$repo' 
  AND date >= '$DATE_START' 
  AND date < '$DATE_END';
SQL
)
  
  TOTAL_ITEMS=$((PR_COUNT + COMMIT_COUNT))
  
  echo "## $repo ($TOTAL_ITEMS items)" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  
  # Write PRs section
  if [ "$PR_COUNT" -gt 0 ]; then
    echo "### Pull Requests ($PR_COUNT)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    sqlite3 -separator '|' "$DB_PATH" "SELECT pr_number, title, state, 
       CASE WHEN merged_at IS NOT NULL THEN 1 ELSE 0 END as merged,
       COALESCE(draft, 0) as is_draft,
       author_span_formatted
FROM prs 
WHERE repo='$repo' 
  AND created_at >= '$DATE_START' 
  AND created_at < '$DATE_END'
ORDER BY created_at DESC;" | while IFS='|' read -r number title state merged draft_flag duration; do
      state_display="$state"
      [ "$draft_flag" = "1" ] && state_display="[draft] $state"
      [ "$merged" = "1" ] && state_display="merged"
      
      pr_url="https://github.com/$repo/pull/$number"
      
      echo "- **PR #$number**: $title" >> "$OUTPUT_FILE"
      echo "  - Status: $state_display" >> "$OUTPUT_FILE"
      echo "  - URL: $pr_url" >> "$OUTPUT_FILE"
      
      # Add duration if available
      if [ -n "$duration" ] && [ "$duration" != "null" ] && [ "$duration" != "0m" ]; then
        echo "  - **Duration:** $duration" >> "$OUTPUT_FILE"
      fi
      
      # Add description if available (query separately to handle multiline)
      # Remove Unicode line/paragraph separators (U+2028, U+2029) that cause editor warnings
      description=$(sqlite3 "$DB_PATH" "SELECT description FROM prs WHERE repo='$repo' AND pr_number=$number;" | head -c 500 | sed $'s/\xe2\x80\xa8/ /g; s/\xe2\x80\xa9/ /g')
      if [ -n "$description" ] && [ "$description" != "null" ]; then
        echo "  ##### Description:" >> "$OUTPUT_FILE"
        echo "  ---" >> "$OUTPUT_FILE"
        echo '  ```' >> "$OUTPUT_FILE"
        echo "$description" | sed 's/^/  /' >> "$OUTPUT_FILE"
        echo '  ```' >> "$OUTPUT_FILE"
        echo "  ---" >> "$OUTPUT_FILE"
      fi
      
      # Add commit details
      echo "  ##### Commits:" >> "$OUTPUT_FILE"
      echo '  ```' >> "$OUTPUT_FILE"
      
      # Get commit count from pr_commits table
      commit_data=$(sqlite3 -separator '|' "$DB_PATH" "SELECT COUNT(*) FROM pr_commits WHERE repo='$repo' AND pr_number=$number;")
      if [ -n "$commit_data" ] && [ "$commit_data" -gt 0 ]; then
        echo "    ($commit_data commits)" >> "$OUTPUT_FILE"
        
        # List commits
        sqlite3 -separator '|' "$DB_PATH" "SELECT author_date, message 
FROM pr_commits 
WHERE repo='$repo' AND pr_number=$number 
ORDER BY author_date;" | while IFS='|' read -r commit_date commit_msg; do
          formatted_date=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$commit_date" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "${commit_date:0:16}")
          echo "    - **${formatted_date}** - ${commit_msg}" >> "$OUTPUT_FILE"
        done
      else
        echo "    (no commit details cached)" >> "$OUTPUT_FILE"
      fi
      
      echo '  ```' >> "$OUTPUT_FILE"
      echo "" >> "$OUTPUT_FILE"
    done
  fi
  
  # Write direct commits section
  if [ "$COMMIT_COUNT" -gt 0 ]; then
    echo "### Direct Commits ($COMMIT_COUNT)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    sqlite3 -separator '|' "$DB_PATH" "SELECT sha, message, date
FROM direct_commits 
WHERE repo='$repo' 
  AND date >= '$DATE_START' 
  AND date < '$DATE_END'
ORDER BY date DESC;" | while IFS='|' read -r sha message date; do
      short_sha="${sha:0:7}"
      short_msg=$(echo "$message" | head -n1 | cut -c1-80)
      echo "- \`$short_sha\` $short_msg _(${date%T*})_" >> "$OUTPUT_FILE"
    done
    
    echo "" >> "$OUTPUT_FILE"
  fi
  
  echo "" >> "$OUTPUT_FILE"
  
done <<< "$REPOS"

echo "✅ Report generated: $OUTPUT_FILE"
