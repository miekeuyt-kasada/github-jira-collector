#!/bin/bash
# Batch analyze diff complexity for multiple PRs
# Usage: ./batch_analyze_diff_complexity.sh <repo> <pr_number1> <pr_number2> ...
# Example: ./batch_analyze_diff_complexity.sh kasada/portal-spa 1709 1726 1739

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO=${1:-}
shift || true

if [ -z "$REPO" ] || [ $# -eq 0 ]; then
  echo "Usage: $0 <repo> <pr_number1> <pr_number2> ..." >&2
  echo "Example: $0 kasada/portal-spa 1709 1726 1739" >&2
  exit 1
fi

PR_NUMBERS=("$@")
TOTAL=${#PR_NUMBERS[@]}

echo "📊 Batch Diff Complexity Analysis"
echo "=================================="
echo "Repo: $REPO"
echo "PRs: ${PR_NUMBERS[*]}"
echo "Total: $TOTAL"
echo ""

count=0
success=0
failed=0

for pr_number in "${PR_NUMBERS[@]}"; do
  count=$((count + 1))
  
  echo "─────────────────────────────────────────────────────────────"
  echo "[$count/$TOTAL] Analyzing PR #$pr_number"
  echo "─────────────────────────────────────────────────────────────"
  echo ""
  
  if "$SCRIPT_DIR/analyze_pr_diff_complexity.sh" "$REPO" "$pr_number"; then
    success=$((success + 1))
  else
    failed=$((failed + 1))
    echo "⚠️  Analysis failed for PR #$pr_number"
  fi
  
  echo ""
done

echo "═══════════════════════════════════════════════════════════════"
echo "✅ Batch analysis complete!"
echo ""
echo "   Success: $success"
echo "   Failed: $failed"
echo "   Total: $TOTAL"
echo "═══════════════════════════════════════════════════════════════"
