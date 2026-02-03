#!/bin/bash
# Enrich LLM-generated brag doc with database metadata
# Usage: ./enrich_bragdoc.sh <llm_output.json> <db_raw_data.json> <output.json>
# Example: ./enrich_bragdoc.sh july-interpreted.json july-raw.json bragdoc-data-2025-07.json

set -e

LLM_OUTPUT="$1"
DB_RAW_DATA="$2"
OUTPUT_FILE="$3"

if [ -z "$LLM_OUTPUT" ] || [ -z "$DB_RAW_DATA" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "Usage: $0 <llm_output.json> <db_raw_data.json> <output.json>" >&2
  exit 1
fi

if [ ! -f "$LLM_OUTPUT" ]; then
  echo "Error: LLM output file not found: $LLM_OUTPUT" >&2
  exit 1
fi

if [ ! -f "$DB_RAW_DATA" ]; then
  echo "Error: DB raw data file not found: $DB_RAW_DATA" >&2
  exit 1
fi

# Use jq to enrich the LLM output with metadata from DB
jq -s '
  .[0] as $llm |
  .[1] as $db |
  
  # Build lookup maps from DB data
  ($db.prs | map({
    key: (.pr_number | tostring),
    value: {
      prId: .pr_number,
      ticketNo: .jira_ticket,
      state: .state,
      dates: {
        start: (.first_commit_date // .created_at),
        end: (.merged_at // .closed_at)
      },
      commitShas: [.commits[].sha],
      repo: .repo
    }
  }) | from_entries) as $pr_lookup |
  
  # Build lookup for direct commits
  ($db.direct_commits | map({
    key: .sha,
    value: {
      commitShas: [.sha],
      dates: {
        start: .date,
        end: .date
      }
    }
  }) | from_entries) as $direct_commit_lookup |
  
  # Process each LLM-generated brag item (handle both wrapped and bare formats on input)
  ($llm | if type == "object" and has("bragItems") then .bragItems elif type == "array" then . else [] end) 
  | map(
      . as $item |
      
      # If item already has prId from LLM, use it directly for lookup
      # This prevents enrichment from overwriting correct LLM-provided IDs
      (if .prId then (.prId | tostring) else null end) as $existing_pr_id |
      
      # Try to extract PR number from achievement text or other fields
      # Look for patterns like "PR #123" or "#123"
      (
        ((.achievement // "") + " " + (.context // "") + " " + (.outcomes // ""))
        | (match("#([0-9]+)"; "g").captures[0].string // null)
      ) as $pr_match |
      
      # Use existing prId from LLM if available, otherwise try pattern matching
      ($existing_pr_id // $pr_match) as $final_pr_match |
      
      # Enrich with metadata if we found a PR match by number
      if $final_pr_match and $pr_lookup[$final_pr_match] then
        . + {
          prId: $pr_lookup[$final_pr_match].prId,
          ticketNo: $pr_lookup[$final_pr_match].ticketNo,
          state: $pr_lookup[$final_pr_match].state,
          commitShas: $pr_lookup[$final_pr_match].commitShas,
          repo: $pr_lookup[$final_pr_match].repo,
          dates: (
            if .dates then .dates 
            else $pr_lookup[$final_pr_match].dates 
            end
          )
        }
      # If no PR number match and no existing prId, try date-based matching
      elif $existing_pr_id == null and (.dates | length > 0) then
        (
          .dates[0] as $start |
          .dates[-1] as $end |
          $db.prs | map(
            select(
              (.first_commit_date[0:10] >= $start and .first_commit_date[0:10] <= $end) or
              (.last_commit_date[0:10] >= $start and .last_commit_date[0:10] <= $end) or
              (.first_commit_date[0:10] <= $start and .last_commit_date[0:10] >= $end)
            ) |
            . + {
              start_match: (if .first_commit_date[0:10] == $start then 10 else 0 end),
              end_match: (if .last_commit_date[0:10] == $end then 10 else 0 end),
              overlap_days: (
                if .first_commit_date[0:10] <= $start and .last_commit_date[0:10] >= $end then 20
                elif .first_commit_date[0:10] >= $start and .last_commit_date[0:10] <= $end then 15
                else 5 end
              )
            }
          ) | sort_by(-(.start_match + .end_match + .overlap_days)) | .[0]
        ) as $date_match |
        
        if $date_match then
          . + {
            prId: $date_match.pr_number,
            ticketNo: $date_match.jira_ticket,
            state: $date_match.state,
            commitShas: [$date_match.commits[].sha],
            repo: $date_match.repo,
            dates: .dates
          }
        else
          # No match found, keep as is
          .
        end
      # If no PR number match and no existing prId and no dates, try fuzzy text matching as last resort
      elif $existing_pr_id == null then
        # Fuzzy text matching
        (
          .achievement as $achievement_text |
          # Extract first 8 words from achievement (usually most distinctive)
          ($achievement_text | ascii_downcase | split(" ") | .[0:8] | map(select(length > 3))) as $achievement_words |
          
          # Score each PR by word overlap with achievement text
          $db.prs | map(
            . as $pr |
            (.title | ascii_downcase) as $pr_title |
            
            # Count matching words with position weighting (earlier words score higher)
            ($achievement_words | to_entries | map(
              .value as $word |
              .key as $position |
              if ($pr_title | contains($word)) then 
                # Earlier words in achievement get higher scores
                (8 - $position)
              else 0 end
            ) | add // 0) as $word_score |
            
            # Bonus for exact phrase matches (first 3 words)
            (if ($achievement_words | length) >= 3 then
              if ($pr_title | contains($achievement_words[0:3] | join(" "))) then 20 else 0 end
            else 0 end) as $phrase_bonus |
            
            # Total score
            ($word_score + $phrase_bonus) as $total_score |
            
            # Only consider PRs with meaningful matches
            select($total_score >= 5) |
            . + {match_score: $total_score}
          ) | sort_by(-.match_score) | .[0]
        ) as $fuzzy_match |
        
        if $fuzzy_match then
          . + {
            prId: $fuzzy_match.pr_number,
            ticketNo: $fuzzy_match.jira_ticket,
            state: $fuzzy_match.state,
            commitShas: [$fuzzy_match.commits[].sha],
            repo: $fuzzy_match.repo,
            dates: {
              start: ($fuzzy_match.first_commit_date[0:10] // null),
              end: ($fuzzy_match.last_commit_date[0:10] // null)
            }
          }
        else
          # No match found by any method, keep as is
          .
        end
      else
        # Item already has prId from LLM, keep as is
        .
      end
    )
' "$LLM_OUTPUT" "$DB_RAW_DATA" > "$OUTPUT_FILE"

echo "✅ Enriched brag doc saved to: $OUTPUT_FILE"

