#!/bin/bash
# Fetch GitHub data (PRs and commits) and cache to SQLite database
# Usage: ./get_github_data.sh [-f] <github_username> <months_back|start_date> [end_date]
# Examples:
#   ./get_github_data.sh miekeuyt 6                       # Last 6 months
#   ./get_github_data.sh miekeuyt 2025/07/01 2025/10/01   # Date range
#   ./get_github_data.sh -f miekeuyt 2025/12/01 2026/01/01  # Force refresh repos cache
#
# To generate markdown reports from cached data:
#   ./generate_report.sh miekeuyt 2025/07/01 2025/10/01

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Parse -f/--force-refresh flag
FORCE_REFRESH=""
POSITIONAL_ARGS=()
for arg in "$@"; do
  case $arg in
    -f|--force-refresh)
      FORCE_REFRESH="-f"
      ;;
    *)
      POSITIONAL_ARGS+=("$arg")
      ;;
  esac
done

# Initialize database
"$SCRIPT_DIR/database/db_init.sh"

USERNAME=${POSITIONAL_ARGS[0]:-"ADD_USER"}

# Detect if second arg is a date or months_back
ARG2="${POSITIONAL_ARGS[1]:-}"
ARG3="${POSITIONAL_ARGS[2]:-}"
ARG4="${POSITIONAL_ARGS[3]:-}"

if [[ "$ARG2" =~ ^[0-9]{4}[/-][0-9]{2}[/-][0-9]{2}$ ]]; then
  # Date range mode
  DATE_START=$(echo "$ARG2" | tr '/' '-')
  DATE_END=$(echo "${ARG3:-$(date +%Y-%m-%d)}" | tr '/' '-')
  
  # For backward compatibility with scripts expecting DATE_BACK
  DATE_BACK="$DATE_START"
else
  # Months back mode (legacy)
  MONTHS_BACK=${ARG2:-6}
  DATE_START=$(date -v-"${MONTHS_BACK}"m +%Y-%m-%d)
  DATE_END=$(date +%Y-%m-%d)
  DATE_BACK="$DATE_START"
fi

echo "Getting repositories..."
REPOS=()

# Calculate months_back for repo fetching (approximate)
if [[ "$ARG2" =~ ^[0-9]{4}[/-][0-9]{2}[/-][0-9]{2}$ ]]; then
  # Calculate approximate months between dates for repo fetch
  start_epoch=$(date -j -f "%Y-%m-%d" "$DATE_START" "+%s" 2>/dev/null || date -d "$DATE_START" "+%s" 2>/dev/null)
  now_epoch=$(date +%s)
  months_diff=$(( (now_epoch - start_epoch) / (30 * 24 * 3600) ))
  MONTHS_FOR_REPOS=$months_diff
else
  MONTHS_FOR_REPOS=$MONTHS_BACK
fi

while IFS= read -r repo; do
  REPOS+=("$repo")
done < <("$SCRIPT_DIR/api/fetch_repos.sh" $FORCE_REFRESH "$USERNAME" "$MONTHS_FOR_REPOS")

for repo in "${REPOS[@]}"; do
  echo "Processing $repo..."
  repo_clean=$(echo "$repo" | tr '/' '-')
  TMP_DIR="/tmp/github_data_${repo_clean}"
  mkdir -p "$TMP_DIR"

  COMMITS_JSON="$TMP_DIR/commits.json"
  PRS_JSON="$TMP_DIR/prs.json"

  "$SCRIPT_DIR/api/get_direct_commits.sh" "$repo" "$USERNAME" "$DATE_START" "$COMMITS_JSON"
  "$SCRIPT_DIR/api/get_prs.sh" "$repo" "$USERNAME" "$DATE_START" "$PRS_JSON"
  "$SCRIPT_DIR/api/get_pr_commits.sh" "$repo" "$USERNAME" "$PRS_JSON" /dev/null "$COMMITS_JSON" "$DATE_START" "$DATE_END"

  rm -rf "$TMP_DIR"
done

echo "✅ GitHub data cached to database"
echo "   To generate markdown report: ./generate_report.sh $USERNAME $DATE_START $DATE_END"