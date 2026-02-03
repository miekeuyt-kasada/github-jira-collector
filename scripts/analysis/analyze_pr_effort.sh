#!/bin/bash
# Analyze PR effort based on timeline, commit tone, PR description, and scope comparison
# Usage: ./analyze_pr_effort.sh <repo> <pr_number>
# Example: ./analyze_pr_effort.sh kasada-io/kasada 1234

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_DIR="$SCRIPT_DIR/../api"
DB_DIR="$SCRIPT_DIR/../database"
# Use environment variable if set, otherwise use default
CACHE_DIR="${CACHE_DIR:-$SCRIPT_DIR/../.cache}"
GITHUB_DB="${GITHUB_DB:-$CACHE_DIR/github_data.db}"
JIRA_DB="${JIRA_DB:-$CACHE_DIR/jira_tickets.db}"

# Source utilities
source "$SCRIPT_DIR/../utils.sh"
source "$DB_DIR/db_helpers.sh"
source "$DB_DIR/jira_helpers.sh"

REPO=${1:-}
PR_NUMBER=${2:-}

if [ -z "$REPO" ] || [ -z "$PR_NUMBER" ]; then
  echo "Usage: $0 <repo> <pr_number>" >&2
  echo "Example: $0 kasada-io/kasada 1234" >&2
  exit 1
fi

if [ ! -f "$GITHUB_DB" ]; then
  echo "Error: GitHub database not found at $GITHUB_DB" >&2
  exit 1
fi

echo "🔍 Analyzing PR #$PR_NUMBER in $REPO..."
echo ""

# ============================================================================
# STEP 1: Fetch PR Data
# ============================================================================

pr_data=$(sqlite3 "$GITHUB_DB" -json "SELECT * FROM prs WHERE repo='$REPO' AND pr_number=$PR_NUMBER" 2>/dev/null | jq '.[0] // null')

if [ "$pr_data" = "null" ] || [ -z "$pr_data" ]; then
  echo "Error: PR #$PR_NUMBER not found in database for repo $REPO" >&2
  exit 1
fi

created_at=$(echo "$pr_data" | jq -r '.created_at')
closed_at=$(echo "$pr_data" | jq -r '.closed_at // "null"')
merged_at=$(echo "$pr_data" | jq -r '.merged_at // "null"')
pr_title=$(echo "$pr_data" | jq -r '.title')
pr_description=$(echo "$pr_data" | jq -r '.description // ""')
jira_ticket=$(echo "$pr_data" | jq -r '.jira_ticket // ""')
state=$(echo "$pr_data" | jq -r '.state_pretty')
# Use author dates for accurate work spread (fallback to committer dates for backward compatibility)
first_commit=$(echo "$pr_data" | jq -r '.first_author_date // .first_commit_date // ""')
last_commit=$(echo "$pr_data" | jq -r '.last_author_date // .last_commit_date // ""')

# Get commits (excluding merge commits)
all_commits=$(sqlite3 "$GITHUB_DB" -json "SELECT * FROM pr_commits WHERE repo='$REPO' AND pr_number=$PR_NUMBER ORDER BY date ASC" 2>/dev/null || echo "[]")
# Filter out merge commits (messages starting with "Merge branch" or "Merge pull request")
commits_data=$(echo "$all_commits" | jq '[.[] | select(.message | startswith("Merge branch") or startswith("Merge pull request") | not)]')
commit_count=$(echo "$commits_data" | jq 'length')
total_commit_count=$(echo "$all_commits" | jq 'length')
merge_commit_count=$((total_commit_count - commit_count))

# Fetch diff stats from GitHub API (additions, deletions, changed files)
diff_stats=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json additions,deletions,changedFiles 2>/dev/null || echo '{"additions":0,"deletions":0,"changedFiles":0}')
additions=$(echo "$diff_stats" | jq -r '.additions // 0')
deletions=$(echo "$diff_stats" | jq -r '.deletions // 0')
changed_files=$(echo "$diff_stats" | jq -r '.changedFiles // 0')
total_changes=$((additions + deletions))

# Check if LLM-analyzed diff complexity is available in DB
llm_diff_complexity=$(echo "$pr_data" | jq -r '.diff_cognitive_complexity // "null"')
if [ "$llm_diff_complexity" = "null" ] || [ -z "$llm_diff_complexity" ]; then
  has_llm_complexity=false
  llm_diff_complexity=0
else
  has_llm_complexity=true
fi

echo "📋 **PR Details**"
echo "   Title: $pr_title"
echo "   State: $state"
echo "   Created: $(format_date_local "$created_at")"
if [ "$closed_at" != "null" ]; then
  echo "   Closed: $(format_date_local "$closed_at")"
fi
if [ -n "$jira_ticket" ] && [ "$jira_ticket" != "null" ]; then
  echo "   JIRA: $jira_ticket"
fi
echo "   Commits: $commit_count"
if [ "$merge_commit_count" -gt 0 ]; then
  echo "   (Excluded $merge_commit_count merge commit(s) from analysis)"
fi
if [ "$total_changes" -gt 0 ]; then
  echo "   Changes: +$additions -$deletions ($changed_files files)"
fi
echo ""

# ============================================================================
# STEP 2: Calculate Base Timeline (excluding weekends)
# ============================================================================

end_time="$closed_at"
if [ "$end_time" = "null" ]; then
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

# Calculate PR span (created → closed)
pr_span_seconds=$(calculate_business_duration "$created_at" "$end_time")
pr_span_days=$(echo "scale=1; $pr_span_seconds / 86400" | bc)

# Always prefer commit span over PR span (reflects actual work time, not waiting time)
commit_span_seconds=0
if [ -n "$first_commit" ] && [ "$first_commit" != "null" ] && [ -n "$last_commit" ] && [ "$last_commit" != "null" ]; then
  commit_span_seconds=$(calculate_business_duration "$first_commit" "$last_commit")
  commit_span_days=$(echo "scale=1; $commit_span_seconds / 86400" | bc)
  
  echo "⏱️  **Base Timeline** (excl. weekends)"
  echo "   PR span (created → closed): $(format_duration_dhm $pr_span_seconds) ($pr_span_days business days)"
  echo "   Commit span (first → last commit): $(format_duration_dhm $commit_span_seconds) ($commit_span_days business days)"
  
  # Use commit span as base (actual work period)
  base_duration_seconds=$commit_span_seconds
  base_duration_days=$commit_span_days
  echo "   Using commit span as base duration"
else
  # Fallback to PR span if no commit data
  echo "⏱️  **Base Timeline** (PR open → close, excl. weekends)"
  echo "   Duration: $(format_duration_dhm $pr_span_seconds) ($pr_span_days business days)"
  base_duration_seconds=$pr_span_seconds
  base_duration_days=$pr_span_days
fi

echo ""

# ============================================================================
# STEP 2b: Check JIRA for Blocked Status (optional adjustment)
# ============================================================================

# If JIRA ticket exists, check if it was blocked during PR timeline
blocked_days=0
if [ -n "$jira_ticket" ] && [ "$jira_ticket" != "null" ]; then
  echo "🚫 **Checking JIRA Blocked Status**"
  
  # Get PR timeline boundaries from commits
  pr_timeline_first=$(echo "$commits_data" | jq -r '.[0].author_date // .[0].date' | cut -d'T' -f1)
  pr_timeline_last=$(echo "$commits_data" | jq -r '.[-1].author_date // .[-1].date' | cut -d'T' -f1)
  
  # Use helper script to get blocked time (uses cache if available)
  blocked_days=$("$SCRIPT_DIR/get_jira_blocked_time.sh" "$jira_ticket" "$pr_timeline_first" "$pr_timeline_last" 2>/dev/null || echo "0")
  
  if [ "$blocked_days" -gt 0 ]; then
    echo "   ⚠️  Ticket was blocked/waiting for $blocked_days day(s) during PR timeline"
    echo "   Subtracting blocked time from base duration"
    
    # Store original for display
    original_base=$base_duration_days
    
    # Subtract blocked days from base timeline
    base_duration_days=$(echo "scale=1; $base_duration_days - $blocked_days" | bc)
    
    # Floor at 0.1 minimum
    base_duration_days=$(echo "scale=1; if ($base_duration_days < 0.1) 0.1 else $base_duration_days" | bc)
    
    echo "   Adjusted base: $base_duration_days days (was $original_base days)"
  else
    echo "   ✓ No blocked status detected during PR timeline"
  fi
fi

echo ""

# ============================================================================
# STEP 3: Find Concurrent PRs (to adjust effort)
# ============================================================================

echo "🔄 **Concurrent PR Activity**"

# Query for other PRs that overlapped with this PR's timeline
concurrent_prs=$(sqlite3 "$GITHUB_DB" -json "
  SELECT pr_number, title, created_at, closed_at, merged_at, first_commit_date, last_commit_date
  FROM prs
  WHERE repo='$REPO'
    AND pr_number != $PR_NUMBER
    AND (
      -- PR was open during our PR's timeline
      (created_at <= '$end_time' AND (closed_at IS NULL OR closed_at >= '$created_at'))
    )
  ORDER BY created_at ASC
" 2>/dev/null || echo "[]")

concurrent_count=$(echo "$concurrent_prs" | jq 'length' 2>/dev/null || echo "0")

if [ "${concurrent_count:-0}" -eq 0 ]; then
  echo "   No concurrent PRs detected."
  adjusted_days=$base_duration_days
else
  echo "   Found $concurrent_count concurrent PR(s):"
  
  # For each concurrent PR, identify overlapping commit days
  # This is a simplified heuristic: we'll count days where commits happened on BOTH PRs
  
  # Get commit dates for current PR (dates only, no time)
  # Use author_date if available, fallback to date (committer date)
  current_pr_dates=$(echo "$commits_data" | jq -r '.[] | .author_date // .date' | cut -d'T' -f1 | sort -u)
  
  concurrent_commit_days=0
  
  echo "$concurrent_prs" | jq -c '.[]' | while IFS= read -r concurrent_pr; do
    concurrent_num=$(echo "$concurrent_pr" | jq -r '.pr_number')
    concurrent_title=$(echo "$concurrent_pr" | jq -r '.title')
    concurrent_created=$(echo "$concurrent_pr" | jq -r '.created_at')
    
    # Get commits for concurrent PR (filter merge commits here too)
    concurrent_commits=$(sqlite3 "$GITHUB_DB" -json "SELECT author_date, date, message FROM pr_commits WHERE repo='$REPO' AND pr_number=$concurrent_num ORDER BY date ASC" 2>/dev/null || echo "[]")
    # Filter merge commits and use author dates
    concurrent_dates=$(echo "$concurrent_commits" | jq -r '.[] | select(.message | startswith("Merge branch") or startswith("Merge pull request") | not) | .author_date // .date' | cut -d'T' -f1 | sort -u)
    
    # Find overlapping dates
    overlap=$(comm -12 <(echo "$current_pr_dates") <(echo "$concurrent_dates") | wc -l | tr -d ' ')
    
    echo "      - PR #$concurrent_num: $concurrent_title"
    echo "        Created: $(format_date_local "$concurrent_created")"
    if [ "$overlap" -gt 0 ]; then
      echo "        ⚠️  $overlap day(s) with overlapping commits"
    fi
  done
  
  # Calculate how many OTHER PRs had commits during this PR's timeline
  # This accounts for interleaved work (e.g., Mon: PR1, Tue: PR2, Wed: PR1)
  
  # Get first and last commit dates for current PR
  current_pr_first=$(echo "$commits_data" | jq -r '.[0].author_date // .[0].date' | cut -d'T' -f1)
  current_pr_last=$(echo "$commits_data" | jq -r '.[-1].author_date // .[-1].date' | cut -d'T' -f1)
  
  # For each concurrent PR, check if it had commits during our timeline
  temp_concurrent_file=$(mktemp)
  echo "$concurrent_prs" | jq -r '.[].pr_number' | while read -r concurrent_num; do
    # Check if this PR had commits between our first and last commit dates
    has_overlap=$(sqlite3 "$GITHUB_DB" "
      SELECT COUNT(*) FROM pr_commits 
      WHERE repo='$REPO' 
        AND pr_number=$concurrent_num
        AND DATE(author_date) BETWEEN DATE('$current_pr_first') AND DATE('$current_pr_last')
    " 2>/dev/null || echo "0")
    
    if [ "$has_overlap" -gt 0 ]; then
      echo "$concurrent_num"
    fi
  done | sort -u > "$temp_concurrent_file"
  
  concurrent_active_prs=$(cat "$temp_concurrent_file")
  rm -f "$temp_concurrent_file"
  
  concurrent_active_count=$(echo "$concurrent_active_prs" | grep -c . || echo "0")
  
  # Adjust timeline based on number of concurrent PRs
  # If N other PRs were active during our timeline, divide by (N+1)
  # Rationale: timeline is shared across all active PRs
  if [ "$concurrent_active_count" -gt 0 ]; then
    divisor=$((concurrent_active_count + 1))
    adjusted_days=$(echo "scale=1; $base_duration_days / $divisor" | bc)
  else
    adjusted_days=$base_duration_days
  fi
  
  # Floor at 0.1 minimum
  adjusted_days=$(echo "scale=1; if ($adjusted_days < 0.1) 0.1 else $adjusted_days" | bc)
  
  echo ""
  echo "   📊 Timeline Adjustment:"
  echo "      - Base: $base_duration_days days"
  echo "      - Concurrent PRs active during timeline: $concurrent_active_count"
  if [ "$concurrent_active_count" -gt 0 ]; then
    echo "      - Divided by: $divisor PRs (this PR + $concurrent_active_count others)"
  fi
  echo "      - Adjusted effort: $adjusted_days days"
fi

echo ""

# ============================================================================
# STEP 4: Analyze Commit Message Tone (effort signals)
# ============================================================================

echo "💬 **Commit Message Analysis**"

# Extract all commit messages
commit_messages=$(echo "$commits_data" | jq -r '.[].message' | tr '[:upper:]' '[:lower:]')

# Count effort-indicating keywords (customized for Mieke's patterns)
# Use grep -c to count lines containing patterns
debug_count=0
refactor_count=0
iteration_count=0
test_count=0
implem_count=0
wip_count=0
typefix_count=0
responsive_count=0
merge_count=0

if [ -n "$commit_messages" ]; then
  # Count lines (commits) containing each pattern
  # Note: grep -c outputs the count even when 0, and returns exit 1 when count is 0
  # We use || true to prevent script exit due to set -e
  debug_count=$(printf "%s\n" "$commit_messages" | grep -ciE "fix|bugfix|bug|oopsie" || true)
  refactor_count=$(printf "%s\n" "$commit_messages" | grep -ciE "refactor|cleanup|cleaner|clean|yeeting|splitting" || true)
  iteration_count=$(printf "%s\n" "$commit_messages" | grep -ciE "pr feedback|pr commento|coderabbit|review" || true)
  test_count=$(printf "%s\n" "$commit_messages" | grep -ciE "test|testing" || true)
  implem_count=$(printf "%s\n" "$commit_messages" | grep -ciE "implem" || true)
  wip_count=$(printf "%s\n" "$commit_messages" | grep -ciE "wip|ugly|basic.*implem|tempfix" || true)
  typefix_count=$(printf "%s\n" "$commit_messages" | grep -ciE "typefix|type fix|eslint" || true)
  responsive_count=$(printf "%s\n" "$commit_messages" | grep -ciE "responsive|aria|a11y|accessibility" || true)
  merge_count=$(printf "%s\n" "$commit_messages" | grep -ciE "merge" || true)
fi

# Ensure all are valid integers (default to 0 if empty)
debug_count=${debug_count:-0}
refactor_count=${refactor_count:-0}
iteration_count=${iteration_count:-0}
test_count=${test_count:-0}
implem_count=${implem_count:-0}
wip_count=${wip_count:-0}
typefix_count=${typefix_count:-0}
responsive_count=${responsive_count:-0}
merge_count=${merge_count:-0}

echo "   Commit themes detected:"
echo "      - Bug fixes:         $debug_count commits"
echo "      - Refactor/Cleanup:  $refactor_count commits"
echo "      - PR iterations:     $iteration_count commits"
echo "      - Implementation:    $implem_count commits"
echo "      - Testing:           $test_count commits"
echo "      - WIP/Iterative:     $wip_count commits"
echo "      - Type/Lint fixes:   $typefix_count commits"
echo "      - Responsive/A11y:   $responsive_count commits"
echo "      - Merge commits:     $merge_count commits"

# Calculate "complexity score" based on commit patterns
# Higher weights for iteration (indicates PR review cycles)
# Note: Refactor/yeeting/fixes might be natural iteration, not extra work
# - "fix" often = fixing bugs you just introduced (getting feature to work)
# - "yeeting" often = removing code you just added (exploration)
# - "refactor" often = refining your own new code
# WIP commits indicate multiple attempts (exploration = effort)

# Ensure all variables are valid integers (default to 0 if empty/invalid)
debug_count=${debug_count:-0}
refactor_count=${refactor_count:-0}
iteration_count=${iteration_count:-0}
wip_count=${wip_count:-0}
typefix_count=${typefix_count:-0}
responsive_count=${responsive_count:-0}

complexity_score=$((debug_count + refactor_count + iteration_count * 3 + wip_count * 2 + typefix_count + responsive_count))

echo ""
echo "   📈 Commit Complexity Score: $complexity_score"
echo "      (Higher = more debugging, refactoring, investigation)"

echo ""

# ============================================================================
# STEP 4b: Analyze Diff Stats (code volume)
# ============================================================================

echo "📊 **Diff Stats Analysis**"

if [ "$total_changes" -gt 0 ]; then
  echo "   Total changes: $total_changes lines (+$additions -$deletions)"
  echo "   Files changed: $changed_files"
  
  # Calculate churn ratio (deletions / additions) - higher = more refactoring
  if [ "$additions" -gt 0 ]; then
    churn_ratio=$(echo "scale=2; $deletions * 100 / $additions" | bc)
    echo "   Churn ratio: ${churn_ratio}% (deletions/additions)"
  else
    churn_ratio=0
  fi
  
  # Calculate diff complexity score
  # If LLM-analyzed score is available, use it (scaled from 0-100 to 0-30)
  # Otherwise, fall back to heuristic based on volume/files/churn
  
  if [ "$has_llm_complexity" = true ]; then
    # Scale LLM score (0-100) to 0-30 range for consistency with other components
    diff_complexity=$(echo "scale=0; $llm_diff_complexity * 0.3" | bc | cut -d'.' -f1)
    
    echo ""
    echo "   📈 Diff Complexity Score: $diff_complexity"
    echo "      (LLM-analyzed cognitive complexity: $llm_diff_complexity/100, scaled × 0.3)"
  else
    # Heuristic fallback: volume + files + churn
    diff_complexity=0
    
    # Total changes contribution (logarithmic scale to prevent huge PRs from dominating)
    if [ "$total_changes" -gt 5000 ]; then
      diff_complexity=$((diff_complexity + 20))
    elif [ "$total_changes" -gt 2000 ]; then
      diff_complexity=$((diff_complexity + 15))
    elif [ "$total_changes" -gt 1000 ]; then
      diff_complexity=$((diff_complexity + 12))
    elif [ "$total_changes" -gt 500 ]; then
      diff_complexity=$((diff_complexity + 8))
    elif [ "$total_changes" -gt 200 ]; then
      diff_complexity=$((diff_complexity + 5))
    elif [ "$total_changes" -gt 100 ]; then
      diff_complexity=$((diff_complexity + 3))
    elif [ "$total_changes" -gt 50 ]; then
      diff_complexity=$((diff_complexity + 2))
    elif [ "$total_changes" -gt 10 ]; then
      diff_complexity=$((diff_complexity + 1))
    fi
    
    # Files changed contribution
    if [ "$changed_files" -gt 50 ]; then
      diff_complexity=$((diff_complexity + 8))
    elif [ "$changed_files" -gt 30 ]; then
      diff_complexity=$((diff_complexity + 5))
    elif [ "$changed_files" -gt 15 ]; then
      diff_complexity=$((diff_complexity + 3))
    elif [ "$changed_files" -gt 5 ]; then
      diff_complexity=$((diff_complexity + 1))
    fi
    
    # Churn bonus (high deletion ratio = refactoring)
    churn_int=$(echo "$churn_ratio" | cut -d'.' -f1)
    if [ "$churn_int" -gt 80 ]; then
      diff_complexity=$((diff_complexity + 3))
    elif [ "$churn_int" -gt 50 ]; then
      diff_complexity=$((diff_complexity + 2))
    elif [ "$churn_int" -gt 30 ]; then
      diff_complexity=$((diff_complexity + 1))
    fi
    
    echo ""
    echo "   📈 Diff Complexity Score: $diff_complexity"
    echo "      (Heuristic: total changes, files touched, churn ratio)"
    echo "      ℹ️  Run analyze_pr_diff_complexity.sh for LLM-based analysis"
  fi
else
  echo "   No diff stats available."
  diff_complexity=0
fi

echo ""

# ============================================================================
# STEP 5: Analyze PR Description Tone
# ============================================================================

echo "📝 **PR Description Analysis**"

if [ -z "$pr_description" ] || [ "$pr_description" = "null" ]; then
  echo "   No PR description found."
  pr_complexity=0
else
  # Count words/lines as basic complexity metric
  word_count=$(echo "$pr_description" | wc -w | tr -d ' ')
  line_count=$(echo "$pr_description" | wc -l | tr -d ' ')
  char_count=$(echo "$pr_description" | wc -c | tr -d ' ')
  
  # Look for complexity indicators in description (customized for Mieke's patterns)
  desc_lower=$(echo "$pr_description" | tr '[:upper:]' '[:lower:]')
  
  # Mieke's structured PR patterns
  has_phases=$(echo "$desc_lower" | grep -qi "phase \d\|##### phase" && echo "Yes" || echo "No")
  has_changelog=$(echo "$desc_lower" | grep -qi "changelog\|commit-by-commit" && echo "Yes" || echo "No")
  has_commit_shas=$(echo "$pr_description" | { grep -oE "[0-9a-f]{7,40}" || true; } | wc -l | tr -d ' ')
  has_deps=$(echo "$desc_lower" | grep -qi "dependency changes\|##### added\|##### removed\|##### updated" && echo "Yes" || echo "No")
  has_key_points=$(echo "$desc_lower" | grep -qi "key points of interest\|## 🔑" && echo "Yes" || echo "No")
  
  # Standard complexity indicators
  has_breaking=$(echo "$desc_lower" | grep -qi "breaking\|migration\|deprecat" && echo "Yes" || echo "No")
  has_technical=$(echo "$desc_lower" | grep -qi "architecture\|design\|pattern\|refactor\|technical" && echo "Yes" || echo "No")
  has_testing=$(echo "$desc_lower" | grep -qi "test\|qa\|verify\|validation" && echo "Yes" || echo "No")
  
  # Check for lists/sections (indicates structured, comprehensive description)
  has_lists=$(echo "$pr_description" | { grep -E "^(\*|-|\d+\.)\s" || true; } | wc -l | tr -d ' ')
  has_sections=$(echo "$pr_description" | { grep -iE "^#{1,6}\s" || true; } | wc -l | tr -d ' ')
  
  echo "   Description length: $word_count words, $line_count lines, $char_count chars"
  echo "   Structural elements: $has_lists lists, $has_sections sections"
  if [ "$has_commit_shas" -gt 0 ]; then
    echo "   Commit SHAs referenced: $has_commit_shas"
  fi
  echo ""
  echo "   Complexity indicators:"
  echo "      - Phased breakdown:           $has_phases"
  echo "      - Commit-by-commit changelog: $has_changelog"
  echo "      - Dependency changes listed:  $has_deps"
  echo "      - Key points section:         $has_key_points"
  echo "      - Breaking changes mentioned: $has_breaking"
  echo "      - Technical depth/design:     $has_technical"
  echo "      - Testing mentioned:          $has_testing"
  
  # Calculate PR description complexity score
  # Very detailed PRs (6000+ chars with phases/changelogs) indicate high effort
  pr_complexity=0
  
  # Base complexity from length (longer = more complex context to manage)
  if [ "$char_count" -gt 6000 ]; then
    pr_complexity=$((pr_complexity + 15))
  elif [ "$char_count" -gt 3000 ]; then
    pr_complexity=$((pr_complexity + 10))
  elif [ "$char_count" -gt 1500 ]; then
    pr_complexity=$((pr_complexity + 5))
  elif [ "$char_count" -gt 500 ]; then
    pr_complexity=$((pr_complexity + 2))
  fi
  
  # Structured documentation patterns (Mieke's style)
  [ "$has_phases" = "Yes" ] && pr_complexity=$((pr_complexity + 8))
  [ "$has_changelog" = "Yes" ] && pr_complexity=$((pr_complexity + 6))
  [ "$has_deps" = "Yes" ] && pr_complexity=$((pr_complexity + 4))
  [ "$has_key_points" = "Yes" ] && pr_complexity=$((pr_complexity + 3))
  [ "$has_commit_shas" -gt 10 ] && pr_complexity=$((pr_complexity + 5))
  
  # Standard indicators
  [ "$has_breaking" = "Yes" ] && pr_complexity=$((pr_complexity + 5))
  [ "$has_technical" = "Yes" ] && pr_complexity=$((pr_complexity + 3))
  [ "$has_testing" = "Yes" ] && pr_complexity=$((pr_complexity + 2))
  
  # Structural elements
  pr_complexity=$((pr_complexity + (has_sections / 2) + (has_lists / 3)))
  
  echo ""
  echo "   📈 PR Description Complexity Score: $pr_complexity"
  echo "      (Higher = more comprehensive, structured, or complex)"
fi

echo ""

# ============================================================================
# STEP 6: Compare with JIRA Ticket (bonus work detection)
# ============================================================================

echo "🎯 **Scope Analysis (JIRA vs PR)**"

if [ -z "$jira_ticket" ] || [ "$jira_ticket" = "null" ] || [ ! -f "$JIRA_DB" ]; then
  echo "   No JIRA ticket associated or JIRA database not available."
  echo "   Cannot assess bonus work."
  bonus_work_score=0
else
  # Fetch JIRA ticket details
  jira_data=$(get_cached_jira_ticket "$jira_ticket")
  
  if [ "$jira_data" = "null" ] || [ -z "$jira_data" ]; then
    echo "   JIRA ticket $jira_ticket not found in cache."
    echo "   Run enrichment script first to cache ticket data."
    bonus_work_score=0
  else
    jira_summary=$(echo "$jira_data" | jq -r '.summary // ""')
    jira_description=$(echo "$jira_data" | jq -r '.description // ""')
    jira_type=$(echo "$jira_data" | jq -r '.issue_type // ""')
    story_points=$(echo "$jira_data" | jq -r '.story_points // ""')
    
    echo "   JIRA Ticket: $jira_ticket"
    echo "   Summary: $jira_summary"
    echo "   Type: $jira_type"
    if [ -n "$story_points" ] && [ "$story_points" != "null" ]; then
      echo "   Story Points: $story_points"
    fi
    echo ""
    
    # Compare PR commit count to story points (if available)
    if [ -n "$story_points" ] && [ "$story_points" != "null" ] && [ "$story_points" != "" ]; then
      # Rough heuristic: 1 story point ≈ 2-5 commits
      expected_commits=$(echo "$story_points * 3" | bc)
      commit_ratio=$(echo "scale=1; $commit_count / $expected_commits" | bc)
      
      echo "   📊 Commit vs Story Points:"
      echo "      - Expected commits: ~$expected_commits (based on $story_points SP)"
      echo "      - Actual commits: $commit_count"
      echo "      - Ratio: ${commit_ratio}x"
      
      if [ "$(echo "$commit_ratio > 1.5" | bc)" -eq 1 ]; then
        echo "      ⚠️  Significantly more commits than expected — possible scope expansion"
      fi
    fi
    
    # Keyword comparison: look for PR work not mentioned in JIRA description
    # Extract key technical terms from PR description and commits (Mieke's patterns)
    # Use printf to ensure proper newline handling
    # Process in smaller chunks to avoid grep hanging
    pr_desc_lower=$(echo "$pr_description" | tr '[:upper:]' '[:lower:]')
    commit_msg_lower=$(echo "$commit_messages" | tr '[:upper:]' '[:lower:]')
    jira_desc_lower=$(echo "$jira_description" | tr '[:upper:]' '[:lower:]')
    
    # Use simpler matching: check for presence rather than extracting all occurrences
    pr_keywords=""
    for keyword in test testing refactor cleanup migration yeeting typefix eslint fix bug bugfix optimization performance security accessibility a11y responsive validation; do
      if echo "$pr_desc_lower $commit_msg_lower" | grep -q "$keyword"; then
        pr_keywords="$pr_keywords $keyword"
      fi
    done
    
    jira_keywords=""
    for keyword in test testing refactor cleanup migration yeeting typefix eslint fix bug bugfix optimization performance security accessibility a11y responsive validation; do
      if echo "$jira_desc_lower" | grep -q "$keyword"; then
        jira_keywords="$jira_keywords $keyword"
      fi
    done
    
    echo ""
    echo "   🔍 Bonus Work Detection:"
    echo "      (Only flags work NOT mentioned OR implied by ticket)"
    echo ""
    
    bonus_work_score=0
    bonus_items=()
    
    # Combine JIRA summary + description + type for implied work detection
    jira_all_text=$(echo "$jira_summary $jira_description $jira_type" | tr '[:upper:]' '[:lower:]')
    
    # Check for work types not mentioned OR IMPLIED by JIRA ticket
    # Based on analysis of 46 actual JIRA tickets (see JIRA_PATTERNS_ANALYSIS.md)
    
    # Testing: IMPLIED for bugs, replacements, removals, validations, migrations
    if echo "$pr_keywords" | grep -qE "\btest\b|\btesting\b" && ! echo "$jira_keywords" | grep -qE "\btest\b|\btesting\b"; then
      # Check if testing is IMPLIED by ticket type/context
      if echo "$jira_type" | grep -qi "bug" || \
         echo "$jira_summary" | grep -qiE "^replace |^remove |migrat|validat"; then
        echo "      ⚠️  Testing added (but implied by ticket: $jira_type / $(echo "$jira_summary" | cut -c1-40)...)"
      else
        echo "      ✅ Testing added (not in ticket scope)"
        bonus_work_score=$((bonus_work_score + 3))
        bonus_items+=("testing")
      fi
    fi
    
    # Refactoring: IMPLIED for chore(DX), migrations, Replace/Remove, consolidation
    if echo "$pr_keywords" | grep -qE "refactor|cleanup" && ! echo "$jira_keywords" | grep -qE "refactor|cleanup"; then
      if echo "$jira_summary" | grep -qiE "chore\(dx\)|^replace |^remove |migrat|consolidat|dry"; then
        echo "      ⚠️  Refactoring/cleanup (but implied by ticket: $(echo "$jira_summary" | cut -c1-40)...)"
      else
        echo "      ✅ Refactoring/cleanup done (not in ticket scope)"
        bonus_work_score=$((bonus_work_score + 3))
        bonus_items+=("refactoring")
      fi
    fi
    
    # Type/lint: IMPLIED for chore(DX), ESLint/TypeScript tickets, migrations
    if echo "$pr_keywords" | grep -qE "typefix|eslint" && ! echo "$jira_keywords" | grep -qE "typefix|eslint"; then
      if echo "$jira_summary" | grep -qiE "chore\(dx\)|eslint|typescript|migrat"; then
        echo "      ⚠️  Type/lint improvements (but implied: $(echo "$jira_summary" | cut -c1-40)...)"
      else
        echo "      ✅ Type/lint improvements (not in ticket scope)"
        bonus_work_score=$((bonus_work_score + 2))
        bonus_items+=("type-safety")
      fi
    fi
    
    # Responsive/A11y: IMPLIED only if explicitly mentioned in summary/description
    if echo "$pr_keywords" | grep -qE "responsive|a11y|accessibility" && ! echo "$jira_keywords" | grep -qE "responsive|a11y|accessibility"; then
      if echo "$jira_summary" | grep -qiE "responsive|mobile|accessib|a11y" || \
         echo "$jira_description" | grep -qiE "responsive|mobile|accessib|a11y"; then
        echo "      ⚠️  Responsive/accessibility work (but explicitly mentioned in ticket)"
      else
        echo "      ✅ Responsive/accessibility improvements (not in ticket scope)"
        bonus_work_score=$((bonus_work_score + 3))
        bonus_items+=("responsive/a11y")
      fi
    fi
    
    if echo "$pr_keywords" | grep -qE "optimization|performance" && ! echo "$jira_keywords" | grep -qE "optimization|performance"; then
      echo "      ✅ Performance optimization (not in ticket scope)"
      bonus_work_score=$((bonus_work_score + 3))
      bonus_items+=("performance")
    fi
    
    # Validation: IMPLIED if ticket is about validation
    if echo "$pr_keywords" | grep -q "validation" && ! echo "$jira_keywords" | grep -q "validation"; then
      if echo "$jira_summary" | grep -qiE "validat|form" && echo "$jira_summary" | grep -qiE "add|creat"; then
        echo "      ⚠️  Validation logic (but implied by validation ticket)"
      else
        echo "      ✅ Validation logic added (not in ticket scope)"
        bonus_work_score=$((bonus_work_score + 2))
        bonus_items+=("validation")
      fi
    fi
    
    if echo "$pr_keywords" | grep -q "migration" && ! echo "$jira_keywords" | grep -q "migration"; then
      echo "      ✅ Migration work (not in ticket scope)"
      bonus_work_score=$((bonus_work_score + 4))
      bonus_items+=("migration")
    fi
    
    # Check for multiple bug fixes (suggests fixing adjacent issues)
    if [ "$debug_count" -gt 3 ] && ! echo "$jira_type" | grep -qi "bug\|fix"; then
      echo "      ✅ Multiple bug fixes in non-bug ticket"
      bonus_work_score=$((bonus_work_score + 2))
      bonus_items+=("bug-fixing")
    fi
    
    # Detect "chore(DX)" work (developer experience improvements)
    if echo "$pr_title" | grep -qi "chore(dx)"; then
      echo "      ✅ Developer experience improvements"
      bonus_work_score=$((bonus_work_score + 2))
      bonus_items+=("DX")
    fi
    
    if [ "$bonus_work_score" -eq 0 ]; then
      echo ""
      echo "      No bonus work detected."
      echo "      (PR scope aligns with ticket, including implied work)"
    else
      echo ""
      echo "   📈 Bonus Work Score: $bonus_work_score"
      echo "      Categories: ${bonus_items[*]}"
      echo ""
      echo "   ℹ️  Note: ⚠️  items were NOT counted as bonus (implied by ticket)"
    fi
  fi
fi

echo ""
echo ""

# ============================================================================
# STEP 7: Summary Report
# ============================================================================

echo "📊 **EFFORT SUMMARY**"
echo "================================"
echo ""
echo "**Timeline Metrics:**"
echo "   - Base duration (excl. weekends): $base_duration_days days"
echo "   - Adjusted duration (excl. concurrent PR work): $adjusted_days days"
if [ -n "$first_commit" ] && [ "$first_commit" != "null" ] && [ -n "$last_commit" ] && [ "$last_commit" != "null" ]; then
  commit_span_seconds=$(calculate_business_duration "$first_commit" "$last_commit")
  commit_span_formatted=$(format_duration_dhm "$commit_span_seconds")
  echo "   - First commit → Last commit: $commit_span_formatted"
else
  echo "   - First commit → Last commit: N/A"
fi
echo ""
echo "**Complexity Signals:**"
echo "   - Commit complexity score: $complexity_score"
echo "   - Diff complexity score: $diff_complexity"
echo "   - PR description complexity: $pr_complexity"
echo "   - Total commits: $commit_count"
if [ "$total_changes" -gt 0 ]; then
  echo "   - Total changes: $total_changes lines ($changed_files files)"
fi
echo ""
echo "**Bonus Work:**"
echo "   - Bonus work score: $bonus_work_score"
echo ""
echo "**Overall Effort Estimation:**"

# Calculate composite effort score with logarithmic timeline scaling
# Formula: log₂(adjusted_days + 1) * 15 + complexity_score + diff_complexity + pr_complexity + (bonus_work_score * 2)
# Then cap at 100 to keep scores bounded

# Calculate timeline component using logarithmic scale
timeline_component=$(echo "scale=2; l(($adjusted_days + 1)) / l(2) * 15" | bc -l | cut -d'.' -f1)

# Calculate raw composite score
raw_score=$(echo "scale=0; $timeline_component + $complexity_score + $diff_complexity + $pr_complexity + ($bonus_work_score * 2)" | bc | cut -d'.' -f1)

# Cap at 100
if [ "$raw_score" -gt 100 ]; then
  composite_score=100
else
  composite_score=$raw_score
fi

echo "   - Timeline component (log scale): $timeline_component"
echo "   - Raw composite score: $raw_score"
echo "   - Final effort score (capped at 100): $composite_score"
echo ""

# Categorize effort level
if [ "$composite_score" -lt 30 ]; then
  effort_level="Low"
  effort_desc="Simple, straightforward change"
elif [ "$composite_score" -lt 80 ]; then
  effort_level="Medium"
  effort_desc="Moderate complexity, some investigation/refinement"
else
  # Changed threshold from 150 to 100 since we cap at 100
  effort_level="High"
  effort_desc="Complex work with significant debugging, refactoring, or scope expansion"
fi

echo "   **Effort Level: $effort_level**"
echo "   $effort_desc"
echo ""

# Ensure numeric variables are valid for JSON
base_duration_days="${base_duration_days:-0}"
adjusted_days="${adjusted_days:-0}"
commit_count="${commit_count:-0}"
complexity_score="${complexity_score:-0}"
diff_complexity="${diff_complexity:-0}"
pr_complexity="${pr_complexity:-0}"
bonus_work_score="${bonus_work_score:-0}"
composite_score="${composite_score:-0}"
additions="${additions:-0}"
deletions="${deletions:-0}"
changed_files="${changed_files:-0}"

# Clean any whitespace
base_duration_days=$(echo "$base_duration_days" | tr -d ' ')
adjusted_days=$(echo "$adjusted_days" | tr -d ' ')
commit_count=$(echo "$commit_count" | tr -d ' ')

# JSON output for programmatic use
json_output=$(jq -n \
  --arg pr "$PR_NUMBER" \
  --arg repo "$REPO" \
  --arg title "$pr_title" \
  --arg jira "$jira_ticket" \
  --argjson base_days "$base_duration_days" \
  --argjson adjusted_days "$adjusted_days" \
  --argjson commit_count "$commit_count" \
  --argjson commit_complexity "$complexity_score" \
  --argjson diff_complexity "$diff_complexity" \
  --argjson llm_diff_complexity "$llm_diff_complexity" \
  --argjson pr_complexity "$pr_complexity" \
  --argjson bonus_score "$bonus_work_score" \
  --argjson composite "$composite_score" \
  --argjson additions "$additions" \
  --argjson deletions "$deletions" \
  --argjson changed_files "$changed_files" \
  --arg effort_level "$effort_level" \
  --arg effort_desc "$effort_desc" \
  '{
    pr_number: $pr,
    repo: $repo,
    title: $title,
    jira_ticket: $jira,
    timeline: {
      base_days: $base_days,
      adjusted_days: $adjusted_days
    },
    complexity: {
      commit_count: $commit_count,
      commit_complexity_score: $commit_complexity,
      diff_complexity_score: $diff_complexity,
      llm_diff_cognitive_complexity: $llm_diff_complexity,
      pr_description_complexity: $pr_complexity
    },
    diff_stats: {
      additions: $additions,
      deletions: $deletions,
      changed_files: $changed_files
    },
    bonus_work_score: $bonus_score,
    composite_effort_score: $composite,
    effort_level: $effort_level,
    effort_description: $effort_desc
  }')

echo "📄 **JSON Output:**"
echo "$json_output" | jq '.'
echo ""

echo "✅ Analysis complete!"
