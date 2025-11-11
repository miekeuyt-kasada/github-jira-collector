#!/bin/bash
# Shared cross-platform date helpers (macOS + Linux)

format_date_local() {
  local input="$1"
  if [ -z "$input" ] || [ "$input" = "N/A" ]; then echo "N/A"; return; fi

  if date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$input" "+%s" >/dev/null 2>&1; then
    # macOS (BSD date)
    utc_epoch=$(date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$input" "+%s")
    date -r "$utc_epoch" "+%Y-%m-%d %H:%M"
  else
    # Linux
    date -d "$input" "+%Y-%m-%d %H:%M"
  fi
}

to_epoch() {
  local input="$1"
  if date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$input" "+%s" >/dev/null 2>&1; then
    date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$input" "+%s"
  else
    date -d "$input" "+%s"
  fi
}
# --- Convert seconds into "Xd Yh Zm" ---
format_duration_dhm() {
  local total_seconds=$1

  # Guard: handle empty or invalid input
  if [ -z "$total_seconds" ] || ! [[ "$total_seconds" =~ ^[0-9]+$ ]]; then
    echo "0m"
    return
  fi

  local days=$(( total_seconds / 86400 ))
  local hours=$(( (total_seconds % 86400) / 3600 ))
  local minutes=$(( (total_seconds % 3600) / 60 ))

  if [ $days -gt 0 ]; then
    if [ $minutes -gt 0 ]; then
      echo "${days}d ${hours}h ${minutes}m"
    else
      echo "${days}d ${hours}h"
    fi
  elif [ $hours -gt 0 ]; then
    if [ $minutes -gt 0 ]; then
      echo "${hours}h ${minutes}m"
    else
      echo "${hours}h"
    fi
  else
    echo "${minutes}m"
  fi
}

# --- Compute duration between now and a given ISO timestamp (UTC) ---
format_duration_since() {
  local start_time="$1"
  local start_epoch now_epoch

  start_epoch=$(to_epoch "$start_time")
  now_epoch=$(date -u +%s)   # 👈 use -u so both are UTC

  if [ "$start_epoch" -eq 0 ]; then
    echo "N/A"
    return
  fi

  local duration_seconds=$((now_epoch - start_epoch))
  format_duration_dhm "$duration_seconds"
}

# --- Calculate business days between two ISO timestamps ---
calculate_business_days() {
  local start_time="$1"
  local end_time="$2"
  
  local start_epoch=$(to_epoch "$start_time")
  local end_epoch=$(to_epoch "$end_time")
  
  if [ "$start_epoch" -eq 0 ] || [ "$end_epoch" -eq 0 ]; then
    echo "0"
    return
  fi
  
  # Start from the beginning of start_time day
  local current_epoch=$start_epoch
  local business_days=0
  local seconds_per_day=86400
  
  # Iterate through each day
  while [ $current_epoch -lt $end_epoch ]; do
    # Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
    if date -j -f "%s" "$current_epoch" "+%w" >/dev/null 2>&1; then
      # macOS
      day_of_week=$(date -j -f "%s" "$current_epoch" "+%w")
    else
      # Linux
      day_of_week=$(date -d "@$current_epoch" "+%w")
    fi
    
    # Count if it's a weekday (1-5 = Monday-Friday)
    if [ "$day_of_week" -ge 1 ] && [ "$day_of_week" -le 5 ]; then
      business_days=$((business_days + 1))
    fi
    
    current_epoch=$((current_epoch + seconds_per_day))
  done
  
  echo "$business_days"
}

# --- Calculate duration excluding weekend time ---
calculate_business_duration() {
  local start_time="$1"
  local end_time="$2"
  
  local start_epoch=$(to_epoch "$start_time")
  local end_epoch=$(to_epoch "$end_time")
  
  if [ "$start_epoch" -eq 0 ] || [ "$end_epoch" -eq 0 ]; then
    echo "0"
    return
  fi
  
  local total_seconds=0
  local current_epoch=$start_epoch
  local seconds_per_day=86400
  
  # Iterate through each full day
  while [ $((current_epoch + seconds_per_day)) -le $end_epoch ]; do
    # Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
    if date -j -f "%s" "$current_epoch" "+%w" >/dev/null 2>&1; then
      # macOS
      day_of_week=$(date -j -f "%s" "$current_epoch" "+%w")
    else
      # Linux
      day_of_week=$(date -d "@$current_epoch" "+%w")
    fi
    
    # Add full day if it's a weekday (1-5 = Monday-Friday)
    if [ "$day_of_week" -ge 1 ] && [ "$day_of_week" -le 5 ]; then
      total_seconds=$((total_seconds + seconds_per_day))
    fi
    
    current_epoch=$((current_epoch + seconds_per_day))
  done
  
  # Handle remaining partial day
  local remaining_seconds=$((end_epoch - current_epoch))
  if [ $remaining_seconds -gt 0 ]; then
    # Check if the final partial day is a weekday
    if date -j -f "%s" "$current_epoch" "+%w" >/dev/null 2>&1; then
      day_of_week=$(date -j -f "%s" "$current_epoch" "+%w")
    else
      day_of_week=$(date -d "@$current_epoch" "+%w")
    fi
    
    if [ "$day_of_week" -ge 1 ] && [ "$day_of_week" -le 5 ]; then
      total_seconds=$((total_seconds + remaining_seconds))
    fi
  fi
  
  echo "$total_seconds"
}