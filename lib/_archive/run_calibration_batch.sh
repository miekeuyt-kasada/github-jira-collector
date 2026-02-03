#!/bin/bash
# Run effort analysis on a curated set of PRs for calibration
# Usage: ./run_calibration_batch.sh <repo>
# Example: ./run_calibration_batch.sh kasada/portal-spa

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

REPO=${1:-}

if [ -z "$REPO" ]; then
  echo "Usage: $0 <repo>" >&2
  echo "Example: $0 kasada/portal-spa" >&2
  exit 1
fi

echo "📊 PR Effort Analysis Calibration Batch"
echo "========================================"
echo "Repo: $REPO"
echo ""

# Define 20 PRs spanning different complexity levels
# Based on commit count distribution from kasada/portal-spa

# Small PRs (1-4 commits): Quick fixes, simple chores
small_prs=(1893 1892 1806 1771 1772 1790)

# Medium PRs (5-12 commits): Standard features, moderate refactors
medium_prs=(1800 1807 1805 1709 1765 1757 1708 1735)

# Large PRs (13+ commits): Complex features, major refactors
large_prs=(1863 1837 1817 1825 1748 1769)

# Additional interesting PRs already analyzed
existing_prs=(1726 1739)

# Combine all PRs
all_prs=("${small_prs[@]}" "${medium_prs[@]}" "${large_prs[@]}" "${existing_prs[@]}")

total_prs=${#all_prs[@]}

echo "Selected $total_prs PRs for calibration:"
echo "  - Small (1-4 commits): ${small_prs[*]}"
echo "  - Medium (5-12 commits): ${medium_prs[*]}"
echo "  - Large (13+ commits): ${large_prs[*]}"
echo "  - Previously analyzed: ${existing_prs[*]}"
echo ""

# Create output file for consolidated results
timestamp=$(date +%Y%m%d_%H%M%S)
json_output="$PROJECT_ROOT/calibration_results_${timestamp}.json"
results="[]"

# Counter for progress
count=0

# Analyze each PR
for pr_number in "${all_prs[@]}"; do
  count=$((count + 1))
  
  echo "═══════════════════════════════════════════════════════════════"
  echo "[$count/$total_prs] Analyzing PR #$pr_number"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  
  # Run analysis and capture full output
  output_file="$PROJECT_ROOT/${pr_number}_effort.txt"
  
  if "$SCRIPT_DIR/analyze_pr_effort.sh" "$REPO" "$pr_number" > "$output_file" 2>&1; then
    echo "✅ Saved to: ${pr_number}_effort.txt"
    
    # Extract JSON from output file
    json_data=$(grep -A 100 '^{$' "$output_file" | awk '/^{$/,/^}$/' | jq -s '.[0]' 2>/dev/null || echo "{}")
    
    if [ -n "$json_data" ] && [ "$json_data" != "{}" ]; then
      results=$(echo "$results" | jq --argjson item "$json_data" '. += [$item]')
    fi
  else
    echo "⚠️  Analysis failed for PR #$pr_number"
  fi
  
  echo ""
done

# Save aggregated results
echo "$results" | jq '.' > "$json_output"

echo "═══════════════════════════════════════════════════════════════"
echo "✅ Batch analysis complete!"
echo ""
echo "📄 Consolidated results: $(basename "$json_output")"
echo "📁 Individual reports: {pr_number}_effort.txt (${total_prs} files)"
echo ""

# Quick summary statistics
if [ "$(echo "$results" | jq 'length')" -gt 0 ]; then
  total_analyzed=$(echo "$results" | jq 'length')
  
  low_count=$(echo "$results" | jq '[.[] | select(.effort_level == "Low")] | length')
  medium_count=$(echo "$results" | jq '[.[] | select(.effort_level == "Medium")] | length')
  high_count=$(echo "$results" | jq '[.[] | select(.effort_level == "High")] | length')
  very_high_count=$(echo "$results" | jq '[.[] | select(.effort_level == "Very High")] | length')
  
  avg_composite=$(echo "$results" | jq '[.[].composite_effort_score] | add / length')
  avg_adjusted_days=$(echo "$results" | jq '[.[].timeline.adjusted_days] | add / length')
  
  echo "📊 **Quick Summary**"
  echo "   - Total PRs analyzed: $total_analyzed"
  echo "   - Effort distribution:"
  echo "     • Low: $low_count"
  echo "     • Medium: $medium_count"
  echo "     • High: $high_count"
  echo "     • Very High: $very_high_count"
  echo "   - Average composite score: $(printf "%.0f" $avg_composite)"
  echo "   - Average adjusted days: $(printf "%.1f" $avg_adjusted_days)"
  echo ""
  echo "Next step: Run analyze_calibration.sh on $json_output"
fi

echo "═══════════════════════════════════════════════════════════════"
