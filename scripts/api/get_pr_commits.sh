#!/bin/bash
# Combine PRs, commits, durations, and markdown formatting
# Usage: ./get_pr_commits.sh <repo> <username> <prs_json> <output_md> <commits_json> <date_start> [date_end]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

repo=$1
username=$2
prs_json=$3
output_file=$4
commits_json=$5
DATE_START=$6
DATE_END=${7:-$(date +%Y-%m-%d)}

source "$SCRIPT_DIR/../utils.sh"
source "$SCRIPT_DIR/../database/db_helpers.sh"

> "$output_file"

# Collect PR titles
PR_TITLES=()
while IFS= read -r title; do
  [ -n "$title" ] && PR_TITLES+=("$title")
done < <(cat "$prs_json" | jq -r '.[].title')

# Collect direct commit messages
COMMIT_MESSAGES=()
while IFS= read -r msg; do
  [ -n "$msg" ] && COMMIT_MESSAGES+=("$msg")
done < <(cat "$commits_json" | jq -r '.[].commit.message | split("\n")[0]')

# Identify commits not part of PRs
UNIQUE_COMMITS=()
for msg in "${COMMIT_MESSAGES[@]}"; do
  found=false
  for title in "${PR_TITLES[@]}"; do
    if [[ "$msg" == *"$title"* ]] || [[ "$title" == *"$msg"* ]]; then
      found=true
      break
    fi
  done
  if [ "$found" = false ]; then UNIQUE_COMMITS+=("$msg"); fi
done

# --- Direct Commits Section ---
if [ ${#UNIQUE_COMMITS[@]} -gt 0 ]; then
  echo "### Direct Commits (${#UNIQUE_COMMITS[@]})" >> "$output_file"
  for unique_commit in "${UNIQUE_COMMITS[@]}"; do
    cat "$commits_json" | jq -c --arg commit "$unique_commit" \
      '.[] | select((.commit.message | split("\n")[0]) == $commit)' |
      while IFS= read -r commit_json; do
        commit_date=$(echo "$commit_json" | jq -r '.commit.committer.date')
        commit_message=$(echo "$commit_json" | jq -r '.commit.message' | head -n1)
        formatted_date=$(format_date_local "$commit_date")
        echo "* **${formatted_date}** - ${commit_message}" >> "$output_file"
      done
  done
  echo "" >> "$output_file"
fi

# --- PRs Section ---
# Count PRs within date range
PR_COUNT=$(cat "$prs_json" | jq --arg date_start "$DATE_START" --arg date_end "$DATE_END" \
  '[.[] | select(.created_at >= $date_start and .created_at <= $date_end)] | length' 2>/dev/null || echo 0)
if ! [[ "$PR_COUNT" =~ ^[0-9]+$ ]]; then PR_COUNT=0; fi
if [ "$PR_COUNT" -gt 0 ]; then
  echo "### Pull Requests ($PR_COUNT)" >> "$output_file"

  cat "$prs_json" | jq -r --arg date_start "$DATE_START" --arg date_end "$DATE_END" '
    .[]
    | select(.created_at >= $date_start and .created_at <= $date_end)
    | "PR|" + (.number|tostring)
      + "|" + .created_at
      + "|" + (.closed_at // "N/A")
      + "|" + (.draft | tostring)
      + "|" + .title
      + "|" + (.state // "unknown")
  ' | while IFS='|' read _ pr_number created_at closed_at draft_flag title state; do
    [ -z "$pr_number" ] && continue

    # Check if PR is cached (only for closed/merged PRs)
    if is_pr_cached "$repo" "$pr_number"; then
      echo "  ✓ Using cached data for PR #$pr_number"
      cached=$(get_cached_pr "$repo" "$pr_number")
      
      # Extract pre-computed values from cache
      state_pretty=$(echo "$cached" | jq -r '.pr.state_pretty')
      active_time=$(echo "$cached" | jq -r '.pr.duration_formatted')
      ongoing=$(echo "$cached" | jq -r '.pr.is_ongoing')
      jira_ticket=$(echo "$cached" | jq -r '.pr.jira_ticket // ""')
      commit_span=$(echo "$cached" | jq -r '.pr.commit_span_formatted // ""')
      [ "$ongoing" = "1" ] && ongoing=true || ongoing=false
      open_datetime=$(format_date_local "$(echo "$cached" | jq -r '.pr.created_at')")
      
      closed_at_cached=$(echo "$cached" | jq -r '.pr.closed_at')
      if [ "$closed_at_cached" != "null" ]; then
        close_datetime=$(format_date_local "$closed_at_cached")
      else
        close_datetime="Still open"
      fi
      
      pr_commits=$(echo "$cached" | jq -c '.commits')
    else
      # Not cached or still open - fetch from API
      echo "  → Fetching PR #$pr_number from GitHub API..."
      
      open_datetime=$(format_date_local "$created_at")
      open_epoch=$(to_epoch "$created_at")

      if [ "$closed_at" != "N/A" ]; then
        close_datetime=$(format_date_local "$closed_at")
        close_epoch=$(to_epoch "$closed_at")
        ongoing=false
      else
        close_datetime="Still open"
        close_epoch=$(date +%s)
        ongoing=true
      fi

      # Determine merged vs closed
      merged_at=$(gh api "repos/$repo/pulls/$pr_number" --jq '.merged_at' 2>/dev/null)
      if [ "$state" = "closed" ]; then
        if [ "$merged_at" != "null" ] && [ -n "$merged_at" ]; then
          state_pretty="MERGED"
        else
          state_pretty="CLOSED"
        fi
      else
        state_pretty="OPEN"
      fi

      # Duration calculation (excluding weekends)
      if [ "$ongoing" = true ]; then
        now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        duration_seconds=$(calculate_business_duration "$created_at" "$now_iso")
        active_time=$(format_duration_dhm "$duration_seconds")
      else
        duration_seconds=$(calculate_business_duration "$created_at" "$closed_at")
        active_time=$(format_duration_dhm "$duration_seconds")
      fi
      
      # Extract Jira ticket from title
      jira_ticket=$(echo "$title" | grep -oE '[A-Z]{2,5}-[0-9]{1,5}' | head -n1)
      
      # Fetch commits
      pr_commits=$(gh api --paginate "repos/$repo/pulls/$pr_number/commits" 2>/dev/null)
      
      # Compute commit span for display (excluding weekends)
      if [ "$pr_commits" != "[]" ] && [ -n "$pr_commits" ]; then
        first_commit_date=$(echo "$pr_commits" | jq -r 'sort_by(.commit.committer.date) | .[0].commit.committer.date // ""')
        last_commit_date=$(echo "$pr_commits" | jq -r 'sort_by(.commit.committer.date) | .[-1].commit.committer.date // ""')
        
        if [ -n "$first_commit_date" ] && [ "$first_commit_date" != "null" ]; then
          commit_span_seconds=$(calculate_business_duration "$first_commit_date" "$last_commit_date")
          commit_span=$(format_duration_dhm "$commit_span_seconds")
        else
          commit_span=""
        fi
      else
        commit_span=""
      fi
      
      # Cache this PR (always store, but only use cache for closed/merged)
      # Inject merged_at into the PR JSON (search API doesn't include it)
      pr_full_json=$(cat "$prs_json" | jq --arg pr_num "$pr_number" --arg merged "$merged_at" \
        '.[] | select(.number == ($pr_num | tonumber)) | .merged_at = (if $merged == "null" then null else $merged end)')
      cache_pr "$repo" "$pr_full_json"
      cache_pr_commits "$repo" "$pr_number" "$pr_commits"
    fi

    [ "$ongoing" = true ] && active_display="[ongoing] ${active_time}~" || active_display="$active_time"
    
    [ "$draft_flag" = "true" ] && draft_label="[draft] " || draft_label=""

    # Format Jira ticket for display
    if [ -n "$jira_ticket" ] && [ "$jira_ticket" != "null" ]; then
      jira_display=" [$jira_ticket]"
    else
      jira_display=""
    fi

    echo "#### PR #$pr_number: $title$jira_display" >> "$output_file"
    echo "   - **Opened:** $open_datetime" >> "$output_file"
    echo "   - **Closed:** $close_datetime" >> "$output_file"
    echo "   - **State:** ${draft_label}${state_pretty} (active time: $active_display)" >> "$output_file"
    echo "" >> "$output_file"

    # Description
    description=$(cat "$prs_json" | jq -r --arg pr_num "$pr_number" '.[] | select(.number == ($pr_num | tonumber)) | .body // ""')
    if [ -n "$description" ] && [ "$description" != "null" ]; then
      echo "  ##### Description:" >> "$output_file"
      echo "---" >> "$output_file"
      echo "\`\`\`" >> "$output_file"
      echo "$description" | sed 's/\*/\\*/g; s/_/\\_/g; s/#/\\#/g; s/>/\\>/g; s/`/\\`/g' >> "$output_file"
      echo "\`\`\`" >> "$output_file"
      echo "---" >> "$output_file"
      echo "" >> "$output_file"
    fi

    # Commits inside PR
    echo "   ##### Commits:" >> "$output_file"
    
    if [ -n "$commit_span" ] && [ "$commit_span" != "0m" ]; then
      echo "   **Duration:** $commit_span" >> "$output_file"
      echo "" >> "$output_file"
    fi
    
    echo "\`\`\`" >> "$output_file"

    if [ "$pr_commits" != "[]" ] && [ -n "$pr_commits" ]; then
      total_count=$(echo "$pr_commits" | jq 'length')
      
      # Check if this is cached data (has .author field) or API data (has .author.login)
      is_cached=$(echo "$pr_commits" | jq -r '.[0] | has("author") and (.author | type == "string")')
      
      if [ "$is_cached" = "true" ]; then
        # Cached format: .author is a string
        user_count=$(echo "$pr_commits" | jq --arg username "$username" '[.[] | select(.author == $username)] | length')
        echo "    ($user_count/$total_count commits by $username)" >> "$output_file"
        
        echo "$pr_commits" | jq -c --arg username "$username" '.[] | select(.author == $username)' |
          while IFS= read -r commit_json; do
            commit_date=$(echo "$commit_json" | jq -r '.date')
            commit_message=$(echo "$commit_json" | jq -r '.message')
            formatted_date=$(format_date_local "$commit_date")
            echo "    - **${formatted_date}** - ${commit_message}" >> "$output_file"
          done
      else
        # API format: .author.login
        user_count=$(echo "$pr_commits" | jq --arg username "$username" '[.[] | select(.author.login == $username)] | length')
        echo "    ($user_count/$total_count commits by $username)" >> "$output_file"
        
        echo "$pr_commits" | jq -c --arg username "$username" '.[] | select(.author.login == $username)' |
          while IFS= read -r commit_json; do
            commit_date=$(echo "$commit_json" | jq -r '.commit.committer.date')
            commit_message=$(echo "$commit_json" | jq -r '.commit.message' | head -n1)
            formatted_date=$(format_date_local "$commit_date")
            echo "    - **${formatted_date}** - ${commit_message}" >> "$output_file"
          done
      fi
    fi
    echo "\`\`\`" >> "$output_file"
    echo "" >> "$output_file"
  done

fi