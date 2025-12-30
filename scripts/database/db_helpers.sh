#!/bin/bash
# Database helper functions for GitHub report caching

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/github_report.db"

# Load utility functions for duration calculations
source "$SCRIPT_DIR/../utils.sh"

# Extract Jira ticket number from text (e.g., VIS-454, CORS-3342)
extract_jira_ticket() {
  local text="$1"
  # Match pattern: 2-5 uppercase letters, dash, 1-5 digits
  echo "$text" | grep -oE '[A-Z]{2,5}-[0-9]{1,5}' | head -n1
}

# Check if a PR is cached and closed/merged (immutable)
is_pr_cached() {
  local repo=$1
  local pr_number=$2
  
  result=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM prs WHERE repo='$repo' AND pr_number=$pr_number AND is_ongoing=0" 2>/dev/null)
  [ "$result" = "1" ]
}

# Cache PR metadata with computed stats
cache_pr() {
  local repo=$1
  local pr_json=$2
  
  # Extract fields from JSON
  local pr_number=$(echo "$pr_json" | jq -r '.number')
  local title=$(echo "$pr_json" | jq -r '.title' | sed "s/'/''/g")
  local state=$(echo "$pr_json" | jq -r '.state')
  local draft=$(echo "$pr_json" | jq -r '.draft')
  local created_at=$(echo "$pr_json" | jq -r '.created_at')
  local closed_at=$(echo "$pr_json" | jq -r '.closed_at // "null"')
  local merged_at=$(echo "$pr_json" | jq -r '.merged_at // "null"')
  local description=$(echo "$pr_json" | jq -r '.body // ""' | sed "s/'/''/g")
  local fetched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Extract Jira ticket from title or branch
  local jira_ticket=$(extract_jira_ticket "$title")
  if [ -z "$jira_ticket" ]; then
    # Try branch name if title didn't have a ticket
    local branch=$(echo "$pr_json" | jq -r '.head.ref // ""')
    jira_ticket=$(extract_jira_ticket "$branch")
  fi
  [ -z "$jira_ticket" ] && jira_ticket="null"
  
  # Compute derived fields
  local is_ongoing=1
  local duration_seconds=0
  local state_pretty="OPEN"
  
  if [ "$closed_at" != "null" ]; then
    is_ongoing=0
    
    # Check if merged
    if [ "$merged_at" != "null" ]; then
      state_pretty="MERGED"
    else
      state_pretty="CLOSED"
    fi
    
    # Calculate duration (excluding weekends)
    duration_seconds=$(calculate_business_duration "$created_at" "$closed_at")
  else
    # Still open
    closed_at="null"
    merged_at="null"
    # For ongoing PRs, calculate duration from created_at to now (excluding weekends)
    local now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    duration_seconds=$(calculate_business_duration "$created_at" "$now_iso")
  fi
  
  # Format duration
  local duration_formatted=$(format_duration_dhm "$duration_seconds")
  
  # Convert boolean to integer for SQLite
  [ "$draft" = "true" ] && draft=1 || draft=0
  
  # Insert or replace
  sqlite3 "$DB_PATH" <<EOF
INSERT OR REPLACE INTO prs (
  repo, pr_number, title, state, draft, created_at, closed_at, merged_at,
  description, fetched_at, duration_seconds, duration_formatted, state_pretty, is_ongoing, jira_ticket
) VALUES (
  '$repo', $pr_number, '$title', '$state', $draft, '$created_at', 
  $([ "$closed_at" = "null" ] && echo "NULL" || echo "'$closed_at'"),
  $([ "$merged_at" = "null" ] && echo "NULL" || echo "'$merged_at'"),
  '$description', '$fetched_at', $duration_seconds, '$duration_formatted', '$state_pretty', $is_ongoing,
  $([ "$jira_ticket" = "null" ] && echo "NULL" || echo "'$jira_ticket'")
);
EOF
}

# Cache commits for a PR and compute commit span
cache_pr_commits() {
  local repo=$1
  local pr_number=$2
  local commits_json=$3
  local fetched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Delete existing commits for this PR first
  sqlite3 "$DB_PATH" "DELETE FROM pr_commits WHERE repo='$repo' AND pr_number=$pr_number"
  
  # Get first and last commit dates
  local first_commit_date=$(echo "$commits_json" | jq -r 'sort_by(.commit.committer.date) | .[0].commit.committer.date // ""')
  local last_commit_date=$(echo "$commits_json" | jq -r 'sort_by(.commit.committer.date) | .[-1].commit.committer.date // ""')
  
  # Compute commit span (excluding weekends)
  local commit_span_seconds=0
  local commit_span_formatted=""
  if [ -n "$first_commit_date" ] && [ -n "$last_commit_date" ] && [ "$first_commit_date" != "null" ]; then
    commit_span_seconds=$(calculate_business_duration "$first_commit_date" "$last_commit_date")
    commit_span_formatted=$(format_duration_dhm "$commit_span_seconds")
  fi
  
  # Insert each commit
  echo "$commits_json" | jq -c '.[]' | while IFS= read -r commit; do
    local sha=$(echo "$commit" | jq -r '.sha')
    local author=$(echo "$commit" | jq -r '.author.login // .commit.author.name' | sed "s/'/''/g")
    local date=$(echo "$commit" | jq -r '.commit.committer.date')
    local message=$(echo "$commit" | jq -r '.commit.message' | head -n1 | sed "s/'/''/g")
    
    sqlite3 "$DB_PATH" <<EOF
INSERT OR REPLACE INTO pr_commits (repo, pr_number, sha, author, date, message, fetched_at)
VALUES ('$repo', $pr_number, '$sha', '$author', '$date', '$message', '$fetched_at');
EOF
  done
  
  # Update PR with commit span info
  if [ -n "$first_commit_date" ] && [ "$first_commit_date" != "null" ]; then
    sqlite3 "$DB_PATH" <<EOF
UPDATE prs 
SET first_commit_date = '$first_commit_date',
    last_commit_date = '$last_commit_date',
    commit_span_seconds = $commit_span_seconds,
    commit_span_formatted = '$commit_span_formatted'
WHERE repo = '$repo' AND pr_number = $pr_number;
EOF
  fi
}

# Get cached PR with all metadata and commits
get_cached_pr() {
  local repo=$1
  local pr_number=$2
  
  # Get PR metadata
  pr_data=$(sqlite3 "$DB_PATH" -json "SELECT * FROM prs WHERE repo='$repo' AND pr_number=$pr_number" 2>/dev/null || echo "[]")
  
  # Get commits
  commits_data=$(sqlite3 "$DB_PATH" -json "SELECT * FROM pr_commits WHERE repo='$repo' AND pr_number=$pr_number" 2>/dev/null || echo "[]")
  
  # Ensure valid JSON arrays
  [ -z "$pr_data" ] && pr_data="[]"
  [ -z "$commits_data" ] && commits_data="[]"
  
  # Combine into single JSON object
  echo "$pr_data" | jq --argjson commits "$commits_data" '{pr: .[0], commits: $commits}'
}

# Cache a direct commit (not part of a PR)
cache_direct_commit() {
  local repo=$1
  local commit_json=$2
  local fetched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  local sha=$(echo "$commit_json" | jq -r '.sha')
  local author=$(echo "$commit_json" | jq -r '.author.login // .commit.author.name' | sed "s/'/''/g")
  local date=$(echo "$commit_json" | jq -r '.commit.committer.date')
  local message=$(echo "$commit_json" | jq -r '.commit.message' | head -n1 | sed "s/'/''/g")
  
  sqlite3 "$DB_PATH" <<EOF
INSERT OR IGNORE INTO direct_commits (repo, sha, author, date, message, fetched_at)
VALUES ('$repo', '$sha', '$author', '$date', '$message', '$fetched_at');
EOF
}

# Get cached repos for username and interval (with superset logic + TTL)
# Returns repos if a cached superset exists (earlier or equal since_date) AND is fresh (within 7 days)
get_cached_repos() {
  local username=$1
  local since_date=$2
  local max_age_days=7
  
  # Find the earliest (widest) cached interval that covers our request AND is still fresh
  # Note: datetime() normalizes ISO format (with T and Z) for proper comparison
  local cached_since=$(sqlite3 "$DB_PATH" "
    SELECT since_date FROM repos 
    WHERE username='$username' 
      AND since_date <= '$since_date' 
      AND datetime(fetched_at) >= datetime('now', '-$max_age_days days')
    ORDER BY since_date ASC 
    LIMIT 1
  " 2>/dev/null)
  
  if [ -z "$cached_since" ]; then
    return 1  # No cache hit
  fi
  
  # Return repos from that cached interval
  sqlite3 "$DB_PATH" "
    SELECT DISTINCT repo_name FROM repos 
    WHERE username='$username' AND since_date='$cached_since' 
    ORDER BY repo_name
  " 2>/dev/null
  
  return 0
}

# Cache repos for a specific username and interval
cache_repos() {
  local username=$1
  local since_date=$2
  local repo_list=$3
  local fetched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Insert each repo
  echo "$repo_list" | while IFS= read -r repo_name; do
    [ -z "$repo_name" ] && continue
    
    sqlite3 "$DB_PATH" <<EOF
INSERT OR IGNORE INTO repos (username, since_date, repo_name, fetched_at)
VALUES ('$username', '$since_date', '$repo_name', '$fetched_at');
EOF
  done
}

