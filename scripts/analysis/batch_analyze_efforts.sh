#!/bin/bash
# Batch analyze effort for multiple PRs in a date range
# Usage: ./batch_analyze_efforts.sh <repo> <start_date> <end_date>
# Example: ./batch_analyze_efforts.sh kasada-io/kasada 2025-12-01 2026-01-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
GITHUB_DB="$CACHE_DIR/github_report.db"

REPO=${1:-}
START_DATE=${2:-}
END_DATE=${3:-}

if [ -z "$REPO" ] || [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
  echo "Usage: $0 <repo> <start_date> <end_date>" >&2
  echo "Example: $0 kasada-io/kasada 2025-12-01 2026-01-01" >&2
  exit 1
fi

if [ ! -f "$GITHUB_DB" ]; then
  echo "Error: GitHub database not found at $GITHUB_DB" >&2
  exit 1
fi

echo "📊 Batch Effort Analysis"
echo "========================="
echo "Repo: $REPO"
echo "Date Range: $START_DATE → $END_DATE"
echo ""

# Query PRs in date range
pr_list=$(sqlite3 "$GITHUB_DB" -json "
  SELECT pr_number, title, created_at, state_pretty
  FROM prs
  WHERE repo='$REPO'
    AND created_at >= '$START_DATE'
    AND created_at < '$END_DATE'
  ORDER BY created_at DESC
" 2>/dev/null || echo "[]")

pr_count=$(echo "$pr_list" | jq 'length')

if [ "$pr_count" -eq 0 ]; then
  echo "No PRs found in date range."
  exit 0
fi

echo "Found $pr_count PR(s) to analyze."
echo ""

# Create output file
output_file="pr_effort_analysis_$(date +%Y%m%d_%H%M%S).json"
results="[]"

# Analyze each PR
echo "$pr_list" | jq -c '.[]' | while IFS= read -r pr; do
  pr_number=$(echo "$pr" | jq -r '.pr_number')
  pr_title=$(echo "$pr" | jq -r '.title')
  
  echo "─────────────────────────────────────────────────────────────"
  echo "Analyzing PR #$pr_number: $pr_title"
  echo "─────────────────────────────────────────────────────────────"
  echo ""
  
  # Run analysis and capture JSON output
  analysis_output=$("$SCRIPT_DIR/analyze_pr_effort.sh" "$REPO" "$pr_number" 2>&1 | tail -n 20 | grep -A 100 '^{' | jq -s '.[0]' || echo "{}")
  
  # Append to results
  if [ -n "$analysis_output" ] && [ "$analysis_output" != "{}" ]; then
    results=$(echo "$results" | jq --argjson item "$analysis_output" '. += [$item]')
  fi
  
  echo ""
  echo ""
done

# Save aggregated results
echo "$results" | jq '.' > "$output_file"

echo "═══════════════════════════════════════════════════════════════"
echo "✅ Batch analysis complete!"
echo ""
echo "📄 Results saved to: $output_file"
echo ""

# Summary statistics
total_prs=$(echo "$results" | jq 'length')
avg_adjusted_days=$(echo "$results" | jq '[.[].timeline.adjusted_days] | add / length')
avg_composite=$(echo "$results" | jq '[.[].composite_effort_score] | add / length')
high_effort_count=$(echo "$results" | jq '[.[] | select(.effort_level == "High" or .effort_level == "Very High")] | length')

echo "📊 **Summary Statistics**"
echo "   - Total PRs analyzed: $total_prs"
echo "   - Average adjusted days: $(printf "%.1f" $avg_adjusted_days)"
echo "   - Average composite score: $(printf "%.0f" $avg_composite)"
echo "   - High/Very High effort PRs: $high_effort_count"
echo ""

# Show top 5 by effort
echo "🏆 **Top 5 PRs by Effort:**"
echo "$results" | jq -r '.
  | sort_by(.composite_effort_score) 
  | reverse 
  | .[:5] 
  | .[] 
  | "   #\(.pr_number): \(.title) (score: \(.composite_effort_score), \(.effort_level))"'

echo ""
echo "═══════════════════════════════════════════════════════════════"
