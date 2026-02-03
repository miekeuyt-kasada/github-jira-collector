#!/bin/bash
# Tag Normalization Utilities
# Maps title-case company goals and growth areas to kebab-case format

# Normalize a company goal tag to kebab-case
# Usage: normalize_company_goal_tag "Deliver a positive impact"
# Returns: positive-impact
normalize_company_goal_tag() {
  local input="$1"
  local lowercase=$(echo "$input" | tr '[:upper:]' '[:lower:]')
  
  case "$lowercase" in
    "deliver a positive impact")
      echo "positive-impact"
      ;;
    "be bold, collaborate and innovate")
      echo "collaborate-and-innovate"
      ;;
    "seek to understand")
      echo "seek-to-understand"
      ;;
    "trust and confidentiality")
      echo "trust-and-confidentiality"
      ;;
    "embrace differences and empower others")
      echo "embrace-differences-and-empower-others"
      ;;
    *)
      # If already kebab-case or unknown, return as-is
      echo "$input"
      ;;
  esac
}

# Normalize a growth area tag to kebab-case
# Usage: normalize_growth_area_tag "Decision Making"
# Returns: decision-making
normalize_growth_area_tag() {
  local input="$1"
  local lowercase=$(echo "$input" | tr '[:upper:]' '[:lower:]')
  
  case "$lowercase" in
    "goal oriented")
      echo "goal-oriented"
      ;;
    "decision making")
      echo "decision-making"
      ;;
    "persistence")
      echo "persistence"
      ;;
    "personal accountability")
      echo "personal-accountability"
      ;;
    "growth mindset")
      echo "growth-mindset"
      ;;
    "empathy")
      echo "empathy"
      ;;
    "communication & collaboration"|"communication and collaboration")
      echo "communication-and-collaboration"
      ;;
    "curiosity")
      echo "curiosity"
      ;;
    "customer empathy")
      echo "customer-empathy"
      ;;
    *)
      # If already kebab-case or unknown, return as-is
      echo "$input"
      ;;
  esac
}

# Validate company goal tag is in known list
# Returns 0 if valid, 1 if invalid
validate_company_goal_tag() {
  local tag="$1"
  case "$tag" in
    "positive-impact"|"collaborate-and-innovate"|"seek-to-understand"|"trust-and-confidentiality"|"embrace-differences-and-empower-others")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Validate growth area tag is in known list
# Returns 0 if valid, 1 if invalid
validate_growth_area_tag() {
  local tag="$1"
  case "$tag" in
    "goal-oriented"|"decision-making"|"persistence"|"personal-accountability"|"growth-mindset"|"empathy"|"communication-and-collaboration"|"curiosity"|"customer-empathy")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Normalize a JSON array of company goal objects
# Input: JSON array like [{"tag": "Deliver a positive impact", "description": "..."}]
# Output: Normalized JSON array
normalize_company_goals_json() {
  local json="$1"
  
  # Use jq to transform the array
  echo "$json" | jq -c '[.[] | .tag = (.tag | ascii_downcase | 
    if . == "deliver a positive impact" then "positive-impact"
    elif . == "be bold, collaborate and innovate" then "collaborate-and-innovate"
    elif . == "seek to understand" then "seek-to-understand"
    elif . == "trust and confidentiality" then "trust-and-confidentiality"
    elif . == "embrace differences and empower others" then "embrace-differences-and-empower-others"
    else . end)]'
}

# Normalize a JSON array of growth area objects
# Input: JSON array like [{"tag": "Decision Making", "description": "..."}]
# Output: Normalized JSON array
normalize_growth_areas_json() {
  local json="$1"
  
  # Use jq to transform the array
  echo "$json" | jq -c '[.[] | .tag = (.tag | ascii_downcase | 
    if . == "goal oriented" then "goal-oriented"
    elif . == "decision making" then "decision-making"
    elif . == "persistence" then "persistence"
    elif . == "personal accountability" then "personal-accountability"
    elif . == "growth mindset" then "growth-mindset"
    elif . == "empathy" then "empathy"
    elif (. == "communication & collaboration" or . == "communication and collaboration") then "communication-and-collaboration"
    elif . == "curiosity" then "curiosity"
    elif . == "customer empathy" then "customer-empathy"
    else . end)]'
}

# Get all valid company goal tags
get_valid_company_goals() {
  echo "positive-impact"
  echo "collaborate-and-innovate"
  echo "seek-to-understand"
  echo "trust-and-confidentiality"
  echo "embrace-differences-and-empower-others"
}

# Get all valid growth area tags
get_valid_growth_areas() {
  echo "goal-oriented"
  echo "decision-making"
  echo "persistence"
  echo "personal-accountability"
  echo "growth-mindset"
  echo "empathy"
  echo "communication-and-collaboration"
  echo "curiosity"
  echo "customer-empathy"
}

# Export functions for use in other scripts
export -f normalize_company_goal_tag
export -f normalize_growth_area_tag
export -f validate_company_goal_tag
export -f validate_growth_area_tag
export -f normalize_company_goals_json
export -f normalize_growth_areas_json
export -f get_valid_company_goals
export -f get_valid_growth_areas

