#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../database/db_helpers.sh"

# Load environment variables from .env.local if it exists
if [ -f "$SCRIPT_DIR/../../.env.local" ]; then
  source "$SCRIPT_DIR/../../.env.local"
fi

# Parse arguments
FORCE_REFRESH=false
USERNAME=""
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force-refresh)
      FORCE_REFRESH=true
      shift
      ;;
    --username)
      USERNAME="$2"
      shift 2
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# Use provided username or fall back to env var
USERNAME=${USERNAME:-${GITHUB_USERNAME:-}}

if [ -z "$USERNAME" ]; then
  echo "Error: GitHub username not provided" >&2
  echo "Usage: $0 [--username <username>] [-f] [months_back]" >&2
  echo "  Provide --username flag or set GITHUB_USERNAME environment variable" >&2
  exit 1
fi

MONTHS_BACK=${POSITIONAL_ARGS[0]:-5}
SINCE=$(date -v-"${MONTHS_BACK}"m +"%Y-%m-%d")

# Force refresh: clear cached repos for this user
if [ "$FORCE_REFRESH" = "true" ]; then
  echo "Force refresh: clearing cached repos for $USERNAME" >&2
  sqlite3 "$DB_PATH" "DELETE FROM repos WHERE username='$USERNAME'" 2>/dev/null || true
fi

# Try cache first (skip if force refresh)
if [ "$FORCE_REFRESH" = "false" ] && CACHED_REPOS=$(get_cached_repos "$USERNAME" "$SINCE"); then
  echo "Using cached repos for $USERNAME since $SINCE or earlier" >&2
  echo "$CACHED_REPOS"
  exit 0
fi

echo "Fetching repo list for $USERNAME since $SINCE (MONTHS_BACK=$MONTHS_BACK)..." >&2

MY_REPOS=$(gh repo list --json nameWithOwner --jq '.[].nameWithOwner')

KASADA_REPOS=$(
  gh repo list kasada \
    --limit 1000 --source \
    --json nameWithOwner,pushedAt,isEmpty,isArchived \
  | jq -r --arg SINCE "$SINCE" '
      .[]
      | select(.pushedAt > $SINCE and .isEmpty == false and .isArchived == false)
      | .nameWithOwner
    ' \
  | xargs -P 8 -I {} bash -c '
      repo="{}"
      if gh api "repos/$repo/contributors" --jq ".[].login" 2>/dev/null | grep -qx "'$USERNAME'"; then
        echo "$repo"
      fi
    '
)

COMBINED_REPOS=$( (echo "$MY_REPOS"; echo "$KASADA_REPOS") | sort -u )

# Cache and output the results
cache_repos "$USERNAME" "$SINCE" "$COMBINED_REPOS"
echo "$COMBINED_REPOS"