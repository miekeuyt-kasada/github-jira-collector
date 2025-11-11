#!/bin/bash
# Fetch PRs authored by user
# Usage: ./get_prs.sh <repo> <username> <date_back> <output_json>

repo=$1
username=$2
date_back=$3
output_file=$4

echo "  Fetching PRs for $repo..."
> "$output_file"

PAGE=1
while true; do
  query="is:pr+author:$username+repo:$repo"
  response=$(gh api "/search/issues?q=$query&per_page=100&page=$PAGE")
  items=$(echo "$response" | jq '.items // []')
  [ "$items" = "[]" ] && break
  echo "$items" >> "$output_file"
  count=$(echo "$items" | jq '. | length')
  [ "$count" -lt 100 ] && break
  PAGE=$((PAGE + 1))
done