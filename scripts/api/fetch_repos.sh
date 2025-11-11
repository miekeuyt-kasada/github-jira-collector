#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../database/db_helpers.sh"

USERNAME=${1:-miekeuyt-kasada}
MONTHS_BACK=${2:-5}
SINCE=$(date -v-"${MONTHS_BACK}"m +"%Y-%m-%d")

# Try cache first
if CACHED_REPOS=$(get_cached_repos "$USERNAME" "$SINCE"); then
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