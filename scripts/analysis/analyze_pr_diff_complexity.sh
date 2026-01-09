#!/bin/bash
# Analyze PR diff complexity using LLM reasoning
# Usage: ./analyze_pr_diff_complexity.sh <repo> <pr_number>
# Example: ./analyze_pr_diff_complexity.sh kasada/portal-spa 1709

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
GITHUB_DB="$CACHE_DIR/github_report.db"

REPO=${1:-}
PR_NUMBER=${2:-}

if [ -z "$REPO" ] || [ -z "$PR_NUMBER" ]; then
  echo "Usage: $0 <repo> <pr_number>" >&2
  echo "Example: $0 kasada/portal-spa 1234" >&2
  exit 1
fi

if [ ! -f "$GITHUB_DB" ]; then
  echo "Error: GitHub database not found at $GITHUB_DB" >&2
  exit 1
fi

echo "🔍 Analyzing diff complexity for PR #$PR_NUMBER in $REPO..."
echo ""

# Check if already analyzed
existing=$(sqlite3 "$GITHUB_DB" "SELECT diff_cognitive_complexity FROM prs WHERE repo='$REPO' AND pr_number=$PR_NUMBER" 2>/dev/null || echo "")

if [ -n "$existing" ] && [ "$existing" != "" ]; then
  echo "✓ Already analyzed: complexity score = $existing"
  echo "  (Use --force to re-analyze)"
  exit 0
fi

# Fetch PR diff
echo "📥 Fetching diff from GitHub..."
DIFF_FILE=$(mktemp)

if ! gh pr diff "$PR_NUMBER" --repo "$REPO" > "$DIFF_FILE" 2>/dev/null; then
  echo "Error: Failed to fetch PR diff" >&2
  exit 1
fi

DIFF_SIZE=$(wc -l < "$DIFF_FILE" | tr -d ' ')
echo "   Diff size: $DIFF_SIZE lines"

# Filter diff by file type
# Ignore: lockfiles, generated code, build artifacts
# Reduce weight: tests, type definitions
echo ""
echo "🔧 Filtering diff..."

FILTERED_DIFF=$(mktemp)

awk '
BEGIN { 
  current_file = ""
  skip_file = 0
  weight = 1.0
  in_chunk = 0
}

# Track current file
/^diff --git/ {
  current_file = $0
  
  # Files to completely ignore
  if (current_file ~ /lock\.(json|yaml|yml)$/ || 
      current_file ~ /package-lock\.json$/ ||
      current_file ~ /yarn\.lock$/ ||
      current_file ~ /pnpm-lock\.yaml$/ ||
      current_file ~ /Gemfile\.lock$/ ||
      current_file ~ /Cargo\.lock$/ ||
      current_file ~ /\.generated\.(ts|js|tsx|jsx)$/ ||
      current_file ~ /(dist|build|coverage|\.next)\//) {
    skip_file = 1
    next
  }
  
  # Files with reduced weight (still include but mark)
  if (current_file ~ /\.(test|spec)\.(ts|js|tsx|jsx)$/ ||
      current_file ~ /\.d\.ts$/ ||
      current_file ~ /\/types\// ||
      current_file ~ /__tests__\// ||
      current_file ~ /__mocks__\//) {
    skip_file = 0
    weight = 0.5
    print "# [WEIGHT:0.5] " current_file
    next
  }
  
  # Regular files (full weight)
  skip_file = 0
  weight = 1.0
  print current_file
  next
}

# Print other diff metadata
/^(index|---|\\+\\+\\+|@@)/ {
  if (!skip_file) print
  next
}

# Print actual diff lines
/^[-+ ]/ {
  if (!skip_file) print
}
' "$DIFF_FILE" > "$FILTERED_DIFF"

FILTERED_SIZE=$(wc -l < "$FILTERED_DIFF" | tr -d ' ')
echo "   Filtered diff: $FILTERED_SIZE lines (removed $((DIFF_SIZE - FILTERED_SIZE)) lines)"

if [ "$FILTERED_SIZE" -eq 0 ]; then
  echo ""
  echo "⚠️  No significant code changes detected (only lockfiles/generated code)"
  sqlite3 "$GITHUB_DB" "UPDATE prs SET diff_cognitive_complexity = 0 WHERE repo='$REPO' AND pr_number=$PR_NUMBER"
  echo "   Saved complexity score: 0"
  exit 0
fi

# If diff is too large, sample it intelligently
MAX_LINES=3000
ANALYSIS_DIFF="$FILTERED_DIFF"

if [ "$FILTERED_SIZE" -gt "$MAX_LINES" ]; then
  echo "   Diff too large, sampling key sections..."
  
  # Take first 1000 lines + random 1000 from middle + last 1000 lines
  SAMPLED_DIFF=$(mktemp)
  
  {
    head -1000 "$FILTERED_DIFF"
    echo ""
    echo "# ... (diff continues, sampled middle section) ..."
    echo ""
    tail -n +1000 "$FILTERED_DIFF" | head -n $((FILTERED_SIZE - 2000)) | shuf | head -1000
    echo ""
    echo "# ... (diff continues, final section) ..."
    echo ""
    tail -1000 "$FILTERED_DIFF"
  } > "$SAMPLED_DIFF"
  
  ANALYSIS_DIFF="$SAMPLED_DIFF"
  echo "   Sampled to ~3000 lines for analysis"
fi

# Prepare LLM prompt
echo ""
echo "🤖 Analyzing diff with LLM (via run_cursor_n_times.sh)..."

# Create output file for response
RESPONSE_FILE=$(mktemp)

# Set up cleanup trap for all temp files
cleanup_temp_files() {
  rm -f "$DIFF_FILE" "$FILTERED_DIFF" "$RESPONSE_FILE" 2>/dev/null
  [ -n "${SAMPLED_DIFF:-}" ] && rm -f "$SAMPLED_DIFF" 2>/dev/null
}
trap cleanup_temp_files EXIT

# Build prompt
PROMPT="@${ANALYSIS_DIFF} You are analyzing a GitHub Pull Request diff to assess its cognitive complexity for a developer.

Your task: Assign a cognitive complexity score from 0-100 based on how much mental effort this PR required.

**Scoring Guide (be strict):**
- **0-15**: Pure mechanical changes (import updates, adding/removing constants, copy-paste propagation, config tweaks)
- **15-30**: Systematic refactors with simple pattern (rename across files, API signature changes, simple find-replace)
- **30-50**: Standard features with typical logic (new components, CRUD operations, straightforward state management)
- **50-70**: Complex logic or non-trivial refactors (algorithms, async flows, tricky debugging, architectural understanding needed)
- **70-85**: High complexity work (performance optimization, major migrations, complex state machines, novel patterns)
- **85-100**: Exceptional complexity (system redesign, critical infrastructure, deep domain expertise required)

**Be harsh on mechanical work:**
- Many files touched ≠ complex if pattern is identical
- Deletions are only hard if understanding legacy behavior, not simple removal
- **Tests/types (marked [WEIGHT:0.5]):**
  - NEW tests/test coverage = full value (requires thinking about edge cases)
  - UPDATED test expectations/snapshots = half value (mechanical adjustment)
- Generated code or lockfile updates = 0

**Look for:**
- Novel problem-solving vs copy-paste
- Logic depth (nesting, conditionals, error handling)
- Need to understand system architecture
- Investigation/debugging required

Respond ONLY with:
SCORE: <number>
REASON: <brief explanation>

Write your response to \$1"

# Find run_cursor_n_times.sh
RUN_CURSOR_SCRIPT="$SCRIPT_DIR/../../../steps/run_cursor_n_times.sh"
if [ ! -f "$RUN_CURSOR_SCRIPT" ]; then
  echo "⚠️  run_cursor_n_times.sh not found, using heuristic fallback"
  RESPONSE="SCORE: 50
REASON: Script not found, using default"
else
  # Call via run_cursor_n_times.sh
  if "$RUN_CURSOR_SCRIPT" -o "$RESPONSE_FILE" -c 1 -p "$PROMPT" --model sonnet-4.5 2>&1 | grep -q "failed"; then
    echo "⚠️  LLM call failed, using heuristic fallback"
    RESPONSE="SCORE: 50
REASON: LLM call failed, using default"
  else
    RESPONSE=$(cat "$RESPONSE_FILE" 2>/dev/null || echo "SCORE: 50
REASON: No response file")
  fi
fi

# Parse response
COMPLEXITY_SCORE=$(echo "$RESPONSE" | grep -i "^SCORE:" | head -1 | sed 's/[Ss][Cc][Oo][Rr][Ee]: *//' | tr -d ' ')
COMPLEXITY_REASON=$(echo "$RESPONSE" | grep -i "^REASON:" | head -1 | sed 's/[Rr][Ee][Aa][Ss][Oo][Nn]: *//')

# Validate score
if ! [[ "$COMPLEXITY_SCORE" =~ ^[0-9]+$ ]] || [ "$COMPLEXITY_SCORE" -gt 100 ]; then
  echo "⚠️  Invalid LLM response, using heuristic fallback"
  
  # Fallback: simple heuristic based on filtered diff size and file count
  FILE_COUNT=$(grep -c "^diff --git" "$FILTERED_DIFF" || echo "1")
  
  if [ "$FILTERED_SIZE" -lt 50 ]; then
    COMPLEXITY_SCORE=15
  elif [ "$FILTERED_SIZE" -lt 200 ]; then
    COMPLEXITY_SCORE=30
  elif [ "$FILTERED_SIZE" -lt 500 ]; then
    COMPLEXITY_SCORE=45
  elif [ "$FILTERED_SIZE" -lt 1000 ]; then
    COMPLEXITY_SCORE=60
  else
    COMPLEXITY_SCORE=75
  fi
  
  # Adjust for file count
  if [ "$FILE_COUNT" -gt 30 ]; then
    COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 15))
  elif [ "$FILE_COUNT" -gt 15 ]; then
    COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 10))
  elif [ "$FILE_COUNT" -gt 5 ]; then
    COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 5))
  fi
  
  # Cap at 100
  if [ "$COMPLEXITY_SCORE" -gt 100 ]; then
    COMPLEXITY_SCORE=100
  fi
  
  COMPLEXITY_REASON="Heuristic: ${FILTERED_SIZE} lines, ${FILE_COUNT} files"
fi

echo ""
echo "📊 **Diff Cognitive Complexity**"
echo "   Score: $COMPLEXITY_SCORE / 100"
echo "   Reason: $COMPLEXITY_REASON"

# Save to database
sqlite3 "$GITHUB_DB" "UPDATE prs SET diff_cognitive_complexity = $COMPLEXITY_SCORE WHERE repo='$REPO' AND pr_number=$PR_NUMBER"

echo ""
echo "✅ Saved to database"
