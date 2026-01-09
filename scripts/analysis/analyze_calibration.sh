#!/bin/bash
# Analyze calibration results to identify scoring issues and recommend tweaks
# Usage: ./analyze_calibration.sh <calibration_results.json>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RESULTS_FILE=${1:-}

if [ -z "$RESULTS_FILE" ]; then
  echo "Usage: $0 <calibration_results.json>" >&2
  exit 1
fi

if [ ! -f "$RESULTS_FILE" ]; then
  echo "Error: Results file not found: $RESULTS_FILE" >&2
  exit 1
fi

OUTPUT_FILE="$PROJECT_ROOT/CALIBRATION_ANALYSIS.md"

echo "📊 Analyzing calibration results..."
echo ""

# Load results
results=$(cat "$RESULTS_FILE")
total_prs=$(echo "$results" | jq 'length')

if [ "$total_prs" -eq 0 ]; then
  echo "Error: No results found in $RESULTS_FILE" >&2
  exit 1
fi

echo "Found $total_prs PRs to analyze."
echo ""

# Start building the markdown report
cat > "$OUTPUT_FILE" <<'EOF'
# PR Effort Analysis Calibration Report

This report analyzes the scoring behavior of `analyze_pr_effort.sh` across a diverse set of PRs to identify calibration issues and recommend adjustments.

---

EOF

# ============================================================================
# SECTION 1: Summary Statistics
# ============================================================================

echo "Generating summary statistics..."

low_count=$(echo "$results" | jq '[.[] | select(.effort_level == "Low")] | length')
medium_count=$(echo "$results" | jq '[.[] | select(.effort_level == "Medium")] | length')
high_count=$(echo "$results" | jq '[.[] | select(.effort_level == "High")] | length')
very_high_count=$(echo "$results" | jq '[.[] | select(.effort_level == "Very High")] | length')

min_score=$(echo "$results" | jq '[.[].composite_effort_score] | min')
max_score=$(echo "$results" | jq '[.[].composite_effort_score] | max')
avg_score=$(echo "$results" | jq '[.[].composite_effort_score] | add / length')
median_score=$(echo "$results" | jq '[.[].composite_effort_score] | sort | .[length/2 | floor]')

avg_days=$(echo "$results" | jq '[.[].timeline.adjusted_days] | add / length')
avg_commits=$(echo "$results" | jq '[.[].complexity.commit_count] | add / length')
avg_commit_complexity=$(echo "$results" | jq '[.[].complexity.commit_complexity_score] | add / length')
avg_pr_complexity=$(echo "$results" | jq '[.[].complexity.pr_description_complexity] | add / length')
avg_bonus=$(echo "$results" | jq '[.[].bonus_work_score] | add / length')

cat >> "$OUTPUT_FILE" <<EOF
## 1. Summary Statistics

### Effort Level Distribution

| Level | Count | Percentage |
|-------|-------|------------|
| Low | $low_count | $(echo "scale=1; $low_count * 100 / $total_prs" | bc)% |
| Medium | $medium_count | $(echo "scale=1; $medium_count * 100 / $total_prs" | bc)% |
| High | $high_count | $(echo "scale=1; $high_count * 100 / $total_prs" | bc)% |
| Very High | $very_high_count | $(echo "scale=1; $very_high_count * 100 / $total_prs" | bc)% |

**Current Thresholds:**
- Low: < 30
- Medium: 30-79
- High: 80-149
- Very High: ≥ 150

### Score Distribution

| Metric | Value |
|--------|-------|
| Min composite score | $min_score |
| Max composite score | $max_score |
| Average composite score | $(printf "%.1f" $avg_score) |
| Median composite score | $median_score |

### Component Averages

| Component | Average |
|-----------|---------|
| Adjusted days | $(printf "%.1f" $avg_days) |
| Commit count | $(printf "%.1f" $avg_commits) |
| Commit complexity score | $(printf "%.1f" $avg_commit_complexity) |
| PR description complexity | $(printf "%.1f" $avg_pr_complexity) |
| Bonus work score | $(printf "%.1f" $avg_bonus) |

---

EOF

# ============================================================================
# SECTION 2: Detailed PR Analysis by Category
# ============================================================================

echo "Analyzing PRs by category..."

cat >> "$OUTPUT_FILE" <<'EOF'
## 2. Analysis by PR Size Category

EOF

# Small PRs (1-4 commits)
small_prs=$(echo "$results" | jq '[.[] | select(.complexity.commit_count <= 4)]')
small_count=$(echo "$small_prs" | jq 'length')

if [ "$small_count" -gt 0 ]; then
  small_avg_score=$(echo "$small_prs" | jq '[.[].composite_effort_score] | add / length')
  small_low=$(echo "$small_prs" | jq '[.[] | select(.effort_level == "Low")] | length')
  small_medium=$(echo "$small_prs" | jq '[.[] | select(.effort_level == "Medium")] | length')
  small_high=$(echo "$small_prs" | jq '[.[] | select(.effort_level == "High")] | length')
  
  cat >> "$OUTPUT_FILE" <<EOF
### Small PRs (1-4 commits)

- **Count:** $small_count
- **Average score:** $(printf "%.1f" $small_avg_score)
- **Distribution:** Low: $small_low, Medium: $small_medium, High: $small_high

**Top 5 by score:**

EOF

  echo "$small_prs" | jq -r 'sort_by(.composite_effort_score) | reverse | .[:5] | .[] | "- PR #\(.pr_number): \(.title) — **Score: \(.composite_effort_score)** (\(.effort_level))"' >> "$OUTPUT_FILE"
  
  echo "" >> "$OUTPUT_FILE"
fi

# Medium PRs (5-12 commits)
medium_prs=$(echo "$results" | jq '[.[] | select(.complexity.commit_count >= 5 and .complexity.commit_count <= 12)]')
medium_pr_count=$(echo "$medium_prs" | jq 'length')

if [ "$medium_pr_count" -gt 0 ]; then
  medium_avg_score=$(echo "$medium_prs" | jq '[.[].composite_effort_score] | add / length')
  medium_low=$(echo "$medium_prs" | jq '[.[] | select(.effort_level == "Low")] | length')
  medium_medium=$(echo "$medium_prs" | jq '[.[] | select(.effort_level == "Medium")] | length')
  medium_high=$(echo "$medium_prs" | jq '[.[] | select(.effort_level == "High")] | length')
  
  cat >> "$OUTPUT_FILE" <<EOF
### Medium PRs (5-12 commits)

- **Count:** $medium_pr_count
- **Average score:** $(printf "%.1f" $medium_avg_score)
- **Distribution:** Low: $medium_low, Medium: $medium_medium, High: $medium_high

**Top 5 by score:**

EOF

  echo "$medium_prs" | jq -r 'sort_by(.composite_effort_score) | reverse | .[:5] | .[] | "- PR #\(.pr_number): \(.title) — **Score: \(.composite_effort_score)** (\(.effort_level))"' >> "$OUTPUT_FILE"
  
  echo "" >> "$OUTPUT_FILE"
fi

# Large PRs (13+ commits)
large_prs=$(echo "$results" | jq '[.[] | select(.complexity.commit_count >= 13)]')
large_pr_count=$(echo "$large_prs" | jq 'length')

if [ "$large_pr_count" -gt 0 ]; then
  large_avg_score=$(echo "$large_prs" | jq '[.[].composite_effort_score] | add / length')
  large_low=$(echo "$large_prs" | jq '[.[] | select(.effort_level == "Low")] | length')
  large_medium=$(echo "$large_prs" | jq '[.[] | select(.effort_level == "Medium")] | length')
  large_high=$(echo "$large_prs" | jq '[.[] | select(.effort_level == "High")] | length')
  large_very_high=$(echo "$large_prs" | jq '[.[] | select(.effort_level == "Very High")] | length')
  
  cat >> "$OUTPUT_FILE" <<EOF
### Large PRs (13+ commits)

- **Count:** $large_pr_count
- **Average score:** $(printf "%.1f" $large_avg_score)
- **Distribution:** Low: $large_low, Medium: $large_medium, High: $large_high, Very High: $large_very_high

**Top 5 by score:**

EOF

  echo "$large_prs" | jq -r 'sort_by(.composite_effort_score) | reverse | .[:5] | .[] | "- PR #\(.pr_number): \(.title) — **Score: \(.composite_effort_score)** (\(.effort_level))"' >> "$OUTPUT_FILE"
  
  echo "" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<'EOF'
---

EOF

# ============================================================================
# SECTION 3: Component Weight Analysis
# ============================================================================

echo "Analyzing component weights..."

cat >> "$OUTPUT_FILE" <<'EOF'
## 3. Component Weight Analysis

Current formula: `composite_score = (adjusted_days × 10) + commit_complexity + pr_description_complexity + (bonus_work × 2)`

EOF

# Timeline contribution
echo "$results" | jq -r '.[] | "\(.pr_number)|\(.timeline.adjusted_days)|\(.composite_effort_score)"' | \
  awk -F'|' '{
    days=$2; score=$3;
    timeline_contrib = days * 10;
    pct = (timeline_contrib / score) * 100;
    printf "- PR #%s: adjusted_days=%.1f → timeline contributes %.0f/%.0f (%.0f%%)\n", $1, days, timeline_contrib, score, pct
  }' | head -10 >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" <<'EOF'

### Observations

EOF

# Detect negative adjusted days
negative_days=$(echo "$results" | jq '[.[] | select(.timeline.adjusted_days < 0)]')
negative_count=$(echo "$negative_days" | jq 'length')

if [ "$negative_count" -gt 0 ]; then
  cat >> "$OUTPUT_FILE" <<EOF
**⚠️ Negative Adjusted Days Detected ($negative_count PRs):**

EOF
  echo "$negative_days" | jq -r '.[] | "- PR #\(.pr_number): \(.timeline.base_days) days → **\(.timeline.adjusted_days) adjusted** (composite: \(.composite_effort_score))"' >> "$OUTPUT_FILE"
  cat >> "$OUTPUT_FILE" <<'EOF'

The concurrent PR adjustment is too aggressive for same-day PRs, resulting in negative values and penalizing quick turnaround work.

EOF
fi

# Detect high bonus work impact
high_bonus=$(echo "$results" | jq '[.[] | select(.bonus_work_score > 5)]')
high_bonus_count=$(echo "$high_bonus" | jq 'length')

if [ "$high_bonus_count" -gt 0 ]; then
  cat >> "$OUTPUT_FILE" <<EOF

**Bonus Work Impact ($high_bonus_count PRs with bonus > 5):**

EOF
  echo "$high_bonus" | jq -r '.[] | "- PR #\(.pr_number): bonus=\(.bonus_work_score) → adds \(.bonus_work_score * 2) to score"' | head -5 >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<'EOF'

---

EOF

# ============================================================================
# SECTION 4: Anomalies & Edge Cases
# ============================================================================

echo "Identifying anomalies..."

cat >> "$OUTPUT_FILE" <<'EOF'
## 4. Anomalies & Edge Cases

EOF

# Low scores with high commit counts
low_effort_many_commits=$(echo "$results" | jq '[.[] | select(.effort_level == "Low" and .complexity.commit_count > 5)]')
low_effort_many_count=$(echo "$low_effort_many_commits" | jq 'length')

if [ "$low_effort_many_count" -gt 0 ]; then
  cat >> "$OUTPUT_FILE" <<EOF
### Low Effort PRs with Many Commits ($low_effort_many_count)

These may be under-weighted:

EOF
  echo "$low_effort_many_commits" | jq -r '.[] | "- PR #\(.pr_number) (\(.complexity.commit_count) commits): \(.title) — score: \(.composite_effort_score)"' >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

# High scores with few commits
high_effort_few_commits=$(echo "$results" | jq '[.[] | select((.effort_level == "High" or .effort_level == "Very High") and .complexity.commit_count <= 5)]')
high_effort_few_count=$(echo "$high_effort_few_commits" | jq 'length')

if [ "$high_effort_few_count" -gt 0 ]; then
  cat >> "$OUTPUT_FILE" <<EOF
### High Effort PRs with Few Commits ($high_effort_few_count)

These may be over-weighted or correctly capturing complexity:

EOF
  echo "$high_effort_few_commits" | jq -r '.[] | "- PR #\(.pr_number) (\(.complexity.commit_count) commits): \(.title) — score: \(.composite_effort_score)"' >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

# Long timeline but low score
long_but_low=$(echo "$results" | jq '[.[] | select(.timeline.adjusted_days > 3 and .composite_effort_score < 50)]')
long_but_low_count=$(echo "$long_but_low" | jq 'length')

if [ "$long_but_low_count" -gt 0 ]; then
  cat >> "$OUTPUT_FILE" <<EOF
### Long Timeline but Low Score ($long_but_low_count)

These took time but scored low (possibly blocked/waiting):

EOF
  echo "$long_but_low" | jq -r '.[] | "- PR #\(.pr_number) (\(.timeline.adjusted_days) days): \(.title) — score: \(.composite_effort_score)"' >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<'EOF'
---

EOF

# ============================================================================
# SECTION 5: Recommendations
# ============================================================================

echo "Generating recommendations..."

cat >> "$OUTPUT_FILE" <<'EOF'
## 5. Recommended Calibration Tweaks

Based on the analysis above, here are suggested adjustments:

### 1. Fix Negative Adjusted Days

**Issue:** Concurrent PR adjustment can produce negative values for same-day PRs.

**Recommendation:** Floor adjusted_days at 0.1 minimum:

```bash
# In analyze_pr_effort.sh, after calculating adjusted_days:
adjusted_days=$(echo "scale=1; if ($adjusted_days < 0.1) 0.1 else $adjusted_days" | bc)
```

### 2. Adjust Effort Level Thresholds

**Current thresholds may need tuning based on distribution:**

EOF

# Suggest threshold adjustments based on quartiles
q1=$(echo "$results" | jq '[.[].composite_effort_score] | sort | .[length/4 | floor]')
q2=$(echo "$results" | jq '[.[].composite_effort_score] | sort | .[length/2 | floor]')
q3=$(echo "$results" | jq '[.[].composite_effort_score] | sort | .[3*length/4 | floor]')

cat >> "$OUTPUT_FILE" <<EOF

**Current:** Low < 30, Medium < 80, High < 150

**Data quartiles:** Q1=$q1, Q2=$q2, Q3=$q3

**Suggested (based on quartiles):**
- Low: < $q2 (bottom 50%)
- Medium: $q2 - $q3 (50th-75th percentile)
- High: $q3 - $(echo "$q3 * 2" | bc) (75th-95th percentile)
- Very High: ≥ $(echo "$q3 * 2" | bc) (top 5%)

### 3. Component Weight Tuning

EOF

if [ "$negative_count" -gt 0 ]; then
  cat >> "$OUTPUT_FILE" <<'EOF'
**Timeline weight (currently 10x):**
- Consider reducing to 8x if negative adjustments are common
- Or keep 10x but fix the floor issue

EOF
fi

cat >> "$OUTPUT_FILE" <<'EOF'
**Commit complexity weight (currently 1x):**
- Currently: debug + refactor + (iteration × 3) + (wip × 2) + typefix + responsive
- This seems reasonable, but consider if iteration weight (3x) is appropriate

**PR description complexity (currently 1x):**
- Currently contributes well for detailed PRs
- May want to cap at 20 to prevent over-weighting documentation

**Bonus work multiplier (currently 2x):**
- Check false positives in bonus detection
- Consider reducing to 1.5x if bonus is over-flagged

### 4. Bonus Work Detection Refinement

Review the following for false positives/negatives:

EOF

# Show bonus work distribution
bonus_prs=$(echo "$results" | jq '[.[] | select(.bonus_work_score > 0)]')
bonus_pr_count=$(echo "$bonus_prs" | jq 'length')

cat >> "$OUTPUT_FILE" <<EOF
- $bonus_pr_count/$total_prs PRs received bonus points
- Review individual reports to verify these were truly "bonus" work
- Check for patterns in over/under-detection

EOF

if [ "$bonus_pr_count" -gt 0 ]; then
  cat >> "$OUTPUT_FILE" <<'EOF'

**PRs with bonus work:**

EOF
  echo "$bonus_prs" | jq -r '.[] | "- PR #\(.pr_number): bonus=\(.bonus_work_score) — \(.title)"' | head -10 >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<'EOF'

---

## 6. Next Steps

1. **Manual Review:** Check individual `*_effort.txt` files for PRs that seem mis-scored
2. **Test Tweaks:** Modify `analyze_pr_effort.sh` with suggested changes
3. **Re-run Calibration:** Execute batch again to compare before/after
4. **Iterate:** Adjust thresholds and weights until distribution feels right

---

*Report generated by `analyze_calibration.sh`*
EOF

echo "✅ Calibration analysis complete!"
echo ""
echo "📄 Report saved to: $OUTPUT_FILE"
echo ""
