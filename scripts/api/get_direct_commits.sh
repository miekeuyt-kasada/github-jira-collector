#!/bin/bash
# Fetch direct commits (merge commits, direct pushes)
# Usage: ./get_direct_commits.sh <repo> <username> <date_back> <output_json>

repo=$1
username=$2
date_back=$3
output_file=$4

echo "  Fetching direct commits for $repo..."
> "$output_file"

PAGE=1
while true; do
  response=$(gh api "repos/$repo/commits?author=$username&since=$date_back&per_page=100&page=$PAGE")
  if [ "$response" = "[]" ] || [ -z "$response" ]; then break; fi
  echo "$response" >> "$output_file"
  count=$(echo "$response" | jq '. | length')
  [ "$count" -lt 100 ] && break
  PAGE=$((PAGE + 1))
done