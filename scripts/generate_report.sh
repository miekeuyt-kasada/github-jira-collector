#!/bin/bash
# Generate a GitHub commit + PR report for a user
# Usage: ./generate_report.sh [-f] <github_username> <months_back|start_date> [output_file|end_date] [output_file]
# Examples:
#   ./generate_report.sh miekeuyt 6                       # Last 6 months
#   ./generate_report.sh miekeuyt 2025/07/01 2025/10/01   # Date range
#   ./generate_report.sh -f miekeuyt 2025/12/01 2026/01/01  # Force refresh repos cache

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
  OUTPUT_FILE="${ARG4:-$SCRIPT_DIR/../generated/$USERNAME-commits-${DATE_START}_${DATE_END}.md}"
  
  # For backward compatibility with scripts expecting DATE_BACK
  DATE_BACK="$DATE_START"
else
  # Months back mode (legacy)
  MONTHS_BACK=${ARG2:-6}
  DATE_START=$(date -v-"${MONTHS_BACK}"m +%Y-%m-%d)
  DATE_END=$(date +%Y-%m-%d)
  OUTPUT_FILE="${ARG3:-$SCRIPT_DIR/../generated/$USERNAME-commits-$(date +%Y%m%d).md}"
  DATE_BACK="$DATE_START"
fi

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUTPUT_DIR"

# Write header
echo "# GitHub Commits by $USERNAME" > "$OUTPUT_FILE"
echo "## Period: $DATE_START to $DATE_END" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

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
  TMP_DIR="/tmp/github_report_${repo_clean}"
  mkdir -p "$TMP_DIR"

  COMMITS_JSON="$TMP_DIR/commits.json"
  PRS_JSON="$TMP_DIR/prs.json"
  REPO_OUTPUT="$TMP_DIR/output.md"

  "$SCRIPT_DIR/api/get_direct_commits.sh" "$repo" "$USERNAME" "$DATE_START" "$COMMITS_JSON"
  "$SCRIPT_DIR/api/get_prs.sh" "$repo" "$USERNAME" "$DATE_START" "$PRS_JSON"
  "$SCRIPT_DIR/api/get_pr_commits.sh" "$repo" "$USERNAME" "$PRS_JSON" "$REPO_OUTPUT" "$COMMITS_JSON" "$DATE_START" "$DATE_END"

# --- Count totals for header line (from generated output) ---
TOTAL_UNIQUE=$(grep -oE '^### Direct Commits \([0-9]+\)' "$REPO_OUTPUT" | grep -oE '[0-9]+' | head -n1)
TOTAL_UNIQUE=${TOTAL_UNIQUE:-0}

TOTAL_PRS=$(grep -oE '^### Pull Requests \([0-9]+\)' "$REPO_OUTPUT" | grep -oE '[0-9]+' | head -n1)
TOTAL_PRS=${TOTAL_PRS:-0}

if ! [[ "$TOTAL_UNIQUE" =~ ^[0-9]+$ ]]; then TOTAL_UNIQUE=0; fi
if ! [[ "$TOTAL_PRS" =~ ^[0-9]+$ ]]; then TOTAL_PRS=0; fi

TOTAL_ITEMS=$((TOTAL_PRS + TOTAL_UNIQUE))

echo "## $repo ($TOTAL_ITEMS items)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
cat "$REPO_OUTPUT" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

  rm -rf "$TMP_DIR"
done

echo "✅ Report generated: $OUTPUT_FILE"