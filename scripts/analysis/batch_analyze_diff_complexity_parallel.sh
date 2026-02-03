#!/bin/bash
# Batch analyze PR diff complexity with PARALLEL execution
# Usage: ./batch_analyze_diff_complexity_parallel.sh [--max-parallel N] [--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
GITHUB_DB="$CACHE_DIR/github_data.db"
ANALYZE_SCRIPT="$SCRIPT_DIR/analyze_pr_diff_complexity.sh"

MAX_PARALLEL=5  # Default: 5 concurrent jobs
FORCE_REANALYZE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-parallel)
      MAX_PARALLEL="$2"
      shift 2
      ;;
    --force)
      FORCE_REANALYZE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--max-parallel N] [--force]"
      echo ""
      echo "Options:"
      echo "  --max-parallel N   Run N analyses concurrently (default: 5)"
      echo "  --force            Re-analyze PRs that already have scores"
      echo ""
      echo "This script launches multiple LLM analyses in parallel to speed up"
      echo "batch processing. Each cursor-agent call runs in the background."
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$GITHUB_DB" ]; then
  echo "Error: GitHub database not found at $GITHUB_DB" >&2
  exit 1
fi

if [ ! -f "$ANALYZE_SCRIPT" ]; then
  echo "Error: Analysis script not found at $ANALYZE_SCRIPT" >&2
  exit 1
fi

echo "🔄 Batch PR Diff Complexity Analysis (PARALLEL)"
echo "================================================"
echo ""
echo "Max parallel jobs: $MAX_PARALLEL"
echo ""

# Get PRs to analyze
if [ "$FORCE_REANALYZE" = true ]; then
  echo "Mode: Re-analyzing ALL PRs (--force)"
  prs_to_analyze=$(sqlite3 "$GITHUB_DB" -json "
    SELECT repo, pr_number, title
    FROM prs
    ORDER BY created_at DESC
  ")
else
  echo "Mode: Analyzing PRs WITHOUT LLM scores"
  prs_to_analyze=$(sqlite3 "$GITHUB_DB" -json "
    SELECT repo, pr_number, title
    FROM prs
    WHERE diff_cognitive_complexity IS NULL 
       OR diff_cognitive_complexity = ''
    ORDER BY created_at DESC
  ")
fi

pr_count=$(echo "$prs_to_analyze" | jq 'length')

if [ "$pr_count" -eq 0 ]; then
  echo "✅ No PRs to analyze!"
  exit 0
fi

echo "Found $pr_count PRs to analyze"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Track jobs
declare -a job_pids=()
declare -a job_info=()
completed=0
failed=0
skipped=0

# Temp directory for logs
LOG_DIR=$(mktemp -d)
echo "📝 Logs directory: $LOG_DIR"
echo ""

# Function to wait for a slot
wait_for_slot() {
  while [ ${#job_pids[@]} -ge $MAX_PARALLEL ]; do
    # Check if any job finished
    for i in "${!job_pids[@]}"; do
      pid=${job_pids[$i]}
      if ! kill -0 "$pid" 2>/dev/null; then
        # Job finished
        wait "$pid"
        exit_code=$?
        
        info=${job_info[$i]}
        
        if [ $exit_code -eq 0 ]; then
          echo "  ✅ Completed: $info"
          ((completed++))
        else
          echo "  ❌ Failed: $info (exit $exit_code)"
          ((failed++))
        fi
        
        # Remove from arrays
        unset 'job_pids[$i]'
        unset 'job_info[$i]'
        job_pids=("${job_pids[@]}")
        job_info=("${job_info[@]}")
        
        break
      fi
    done
    
    # Still full? Sleep a bit
    if [ ${#job_pids[@]} -ge $MAX_PARALLEL ]; then
      sleep 1
    fi
  done
}

# Launch analyses
start_time=$(date +%s)

echo "$prs_to_analyze" | jq -c '.[]' | while IFS= read -r pr; do
  repo=$(echo "$pr" | jq -r '.repo')
  pr_number=$(echo "$pr" | jq -r '.pr_number')
  title=$(echo "$pr" | jq -r '.title')
  
  # Check if already analyzed (if not forcing)
  if [ "$FORCE_REANALYZE" = false ]; then
    existing=$(sqlite3 "$GITHUB_DB" "SELECT diff_cognitive_complexity FROM prs WHERE repo='$repo' AND pr_number=$pr_number" 2>/dev/null || echo "")
    if [ -n "$existing" ] && [ "$existing" != "" ]; then
      echo "  ⏭  Skipped: PR #$pr_number (already scored: $existing)"
      ((skipped++))
      continue
    fi
  fi
  
  # Wait for available slot
  wait_for_slot
  
  # Launch analysis in background with timeout
  log_file="$LOG_DIR/pr_${pr_number}.log"
  info="PR #$pr_number - $(echo "$title" | cut -c1-40)..."
  
  echo "  🚀 Starting: $info"
  
  # Wrap in timeout (3 minutes max per PR)
  (timeout 180 "$ANALYZE_SCRIPT" "$repo" "$pr_number" || echo "TIMEOUT after 180s") > "$log_file" 2>&1 &
  pid=$!
  
  job_pids+=($pid)
  job_info+=("$info")
done

# Wait for remaining jobs
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏳ Waiting for remaining jobs to complete..."
echo ""

for i in "${!job_pids[@]}"; do
  pid=${job_pids[$i]}
  info=${job_info[$i]}
  
  if wait "$pid"; then
    echo "  ✅ Completed: $info"
    ((completed++))
  else
    exit_code=$?
    echo "  ❌ Failed: $info (exit $exit_code)"
    ((failed++))
  fi
done

end_time=$(date +%s)
duration=$((end_time - start_time))

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total PRs:      $pr_count"
echo "Completed:      $completed"
echo "Failed:         $failed"
echo "Skipped:        $skipped"
echo ""
echo "Duration:       ${duration}s"
echo "Avg per PR:     $((duration / (completed > 0 ? completed : 1)))s"
echo ""
echo "Logs saved to:  $LOG_DIR"
echo ""

if [ $failed -gt 0 ]; then
  echo "⚠️  Some analyses failed. Check logs for details:"
  echo ""
  grep -l "Error\|Failed" "$LOG_DIR"/*.log 2>/dev/null | while read -r log; do
    pr_num=$(basename "$log" | sed 's/pr_//' | sed 's/.log//')
    echo "  - PR #$pr_num: $log"
  done
  echo ""
fi

if [ $completed -gt 0 ]; then
  echo "✅ Successfully analyzed $completed PRs"
fi

exit 0
