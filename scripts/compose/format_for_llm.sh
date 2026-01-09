#!/bin/bash
# Format database query results into human-readable text for LLM processing
# Usage: ./format_for_llm.sh <json_file>
# Example: ./format_for_llm.sh july-raw.json

set -e

JSON_FILE="$1"

if [ -z "$JSON_FILE" ] || [ ! -f "$JSON_FILE" ]; then
  echo "Usage: $0 <json_file>" >&2
  exit 1
fi

# Use jq to format the data into readable text
jq -r '
  .prs as $prs | 
  .direct_commits as $direct |
  
  # Format PRs
  (if ($prs | length) > 0 then
    "# Pull Requests\n",
    ($prs[] | 
      "\n## PR #\(.pr_number) - \(.repo)\n",
      "Title: \(.title)\n",
      (if .jira_ticket then "JIRA: \(.jira_ticket)\n" else "" end),
      (if .description and (.description | length) > 0 then "Description:\n\(.description)\n" else "" end),
      (
        if .merged_at and .merged_at != "" and .merged_at != "null" then 
          "Status: MERGED on \(.merged_at)\n" 
        elif .closed_at and .closed_at != "" and .closed_at != "null" then 
          "Status: CLOSED (not merged) on \(.closed_at)\n" 
        else 
          "Status: OPEN (created on \(.created_at))\n" 
        end
      ),
      "\nCommits:\n",
      (.commits[] | "- \(.date) | \(.message)")
    )
  else "" end),
  
  # Format direct commits
  (if ($direct | length) > 0 then
    "\n\n# Direct Commits\n",
    ($direct[] | 
      "\n- \(.date) | \(.repo) | \(.message)"
    )
  else "" end)
' "$JSON_FILE"

