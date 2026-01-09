# PR Effort Analysis

Tools for analyzing PR effort based on timeline, commit patterns, PR descriptions, and scope comparison against JIRA tickets.

## Quick Start

### Analyze One PR

```bash
./analyze_pr_effort.sh kasada-io/kasada 1863
```

### Analyze All PRs in a Month

```bash
./batch_analyze_efforts.sh kasada-io/kasada 2025-12-01 2026-01-01
```

### Interpret Scores

- **< 30**: Low (straightforward)
- **30-79**: Medium
- **80-149**: High (complex debugging/refactoring)
- **150+**: Very High (major effort)

---

## What It Does

The effort analysis calculates:

1. **Adjusted Timeline**: PR duration excluding weekends AND days where you worked on concurrent PRs
2. **Commit Complexity**: Patterns in commit messages that signal debugging, refactoring, investigation
3. **PR Description Complexity**: Depth and structure of PR documentation
4. **Bonus Work**: Work done beyond the original JIRA ticket scope

## Scripts

### `analyze_pr_effort.sh`

Analyzes a single PR in depth.

**Usage:**

```bash
./analyze_pr_effort.sh <repo> <pr_number>
```

**Example:**

```bash
./analyze_pr_effort.sh kasada-io/kasada 1234
```

**Output:**

- Detailed console report with metrics broken down by category
- JSON output suitable for programmatic use or piping to other tools

### `batch_analyze_efforts.sh`

Analyzes all PRs in a date range and produces aggregate statistics.

**Usage:**

```bash
./batch_analyze_efforts.sh <repo> <start_date> <end_date>
```

**Example:**

```bash
./batch_analyze_efforts.sh kasada-io/kasada 2025-12-01 2026-01-01
```

**Output:**

- Per-PR analysis printed to console
- Aggregate JSON file: `pr_effort_analysis_YYYYMMDD_HHMMSS.json`
- Summary statistics including averages and top efforts

## Design Decisions

### Customized for Your Patterns

This system was built by analyzing 62 of your PRs and 100+ commit messages to detect:

- **Your commit vocabulary**: "yeeting", "PR commento", "implem", "oopsie" (not generic terms)
- **Your PR structure**: Phased breakdowns, commit-by-commit changelogs, "🔑 Key points"
- **Your bonus work patterns**: Tests/responsive work on non-DX tickets (based on 46 real JIRA tickets)

### Natural Iteration vs Bonus Work

**Reduced weight for fix/refactor/yeeting** (×1 instead of ×2):
- "fix" = often fixing bugs you just introduced
- "yeeting" = often removing code you just added
- "refactor" = often refining your own new code

**Only counts as bonus if**:
- NOT explicitly mentioned in ticket AND
- NOT reasonably implied by ticket type/context (e.g., testing implied for bug fixes)

See archived `DETECTED_PATTERNS.md` and `JIRA_PATTERNS_ANALYSIS.md` for detailed pattern analysis.

## Methodology

### 1. Timeline Adjustment

**Base Duration** = PR created → PR closed (excluding weekends)

**Adjusted Duration** = Base Duration - (Days with concurrent PR commits × 0.5)

The 0.5 multiplier accounts for split attention: if you committed to 2 PRs on the same day, each PR gets ~50% credit for
that day.

**Example:**

- PR open for 10 business days
- 4 days had commits on other PRs
- Adjusted duration = 10 - (4 × 0.5) = 8 days

### 2. Commit Complexity Score

Weighted count of effort-indicating commit message patterns (customized to detect your writing style):

| Pattern          | Weight | Examples                                             | Notes                                              |
| ---------------- | ------ | ---------------------------------------------------- | -------------------------------------------------- |
| PR iterations    | ×3     | "PR feedback", "PR commento", "coderabbit", "review" | External review cycles = clear effort              |
| WIP/Iterative    | ×2     | "wip", "ugly implem", "basic implem", "tempfix"      | Multiple attempts = exploration                    |
| Bug fixes        | ×1     | "fix", "bugfix", "oopsie"                            | Often fixing bugs introduced during implementation |
| Refactor/Cleanup | ×1     | "refactor", "cleanup", "cleaner", "yeeting"          | Might be natural iteration                         |
| Testing          | ×1     | "test", "testing suite"                              |                                                    |
| Type/Lint fixes  | ×1     | "typefix", "type fix", "eslint"                      |                                                    |
| Responsive/A11y  | ×1     | "responsive", "aria", "a11y"                         |                                                    |

**Key Patterns Detected:**

- **"yeeting"**: Code removal — only counts as bonus work if removing _legacy/unrelated_ code (not code added in same
  PR)
- **"fix"**: Bug fixes — only counts as bonus work if fixing _existing_ bugs (not bugs introduced during implementation)
- **"implem"**: Implementation work (basic → proper → ugly indicates iteration)
- **"PR commento"**: Iteration based on review feedback (highest weight = external validation of complexity)
- **"tempfix"**: Temporary solutions (indicates ongoing complexity)

**Important Caveats**:

Three types of commits that look like effort but are often just natural iteration:

1. **"fix"** commits — Often fixing bugs you just introduced while getting the feature to work

   - Natural: `"implem feature"` → `"fix broken tests"` → `"fix edge case"`
   - Bonus work: Fixing 5+ existing/unrelated bugs in a feature PR

2. **"refactor"/"cleanup"** commits — Often refining code you just wrote

   - Natural: Try approach A → refactor to approach B → cleanup
   - Bonus work: Refactoring existing/legacy code outside feature scope

3. **"yeeting"** commits — Often removing code you just added
   - Natural: Add component → doesn't work → yeet → try different approach
   - Bonus work: Removing old/unused code while implementing feature

These are captured as iteration/exploration effort (via WIP count), not as high-complexity or bonus work.

**Interpretation:**

- **0-10**: Straightforward implementation
- **10-30**: Moderate debugging/refinement
- **30+**: Significant investigation, review cycles, or multiple iterations

### 3. PR Description Complexity

Score based on both length and structural patterns (customized to recognize your documentation style):

**Length-based scoring:**

- **6000+ chars**: +15 (extensive documentation)
- **3000-6000**: +10 (detailed)
- **1500-3000**: +5 (moderate)
- **500-1500**: +2 (basic)

**Your structured documentation patterns:**

- **Phase breakdowns** (+8): "Phase 1: Core Migration", "##### Phase 2: Code Fixes"
- **Commit-by-commit changelog** (+6): Detailed changelog with commit SHAs
- **Dependency changes** (+4): "##### Added", "##### Removed", "##### Updated"
- **Key points section** (+3): "## 🔑 Key points of interest"
- **Multiple commit SHAs** (10+): +5 (indicates detailed technical history)
- **Breaking changes** (+5)
- **Technical depth/design** (+3)
- **Testing mentioned** (+2)
- **Structural elements**: Lists and sections (bonus points)

**Interpretation:**

- **0-10**: Minimal or basic description
- **10-25**: Well-documented, structured
- **25-40**: Comprehensive with phases/changelog (typical for major changes)
- **40+**: Extensive technical documentation (ESLint migration level)

### 4. Bonus Work Score

Detects work done beyond JIRA ticket scope by comparing keywords in PR/commits vs JIRA description **and ticket type**
(using your vocabulary).

**Key principle**: Only counts as bonus if work is NOT explicitly mentioned AND NOT reasonably implied by the ticket.

**Data-driven**: Implied work detection is based on analysis of 46 real JIRA tickets (see `JIRA_PATTERNS_ANALYSIS.md`).

| Bonus Work Type            | Score | Detection                                         | Notes                                                      |
| -------------------------- | ----- | ------------------------------------------------- | ---------------------------------------------------------- |
| Migration                  | +4    | "migration" in PR, not in ticket                  |                                                            |
| Testing                    | +3    | "test"/"testing" in PR, not in ticket             |                                                            |
| Refactoring/Cleanup        | +3    | "refactor"/"cleanup" in PR, not in ticket         | Only if refactoring _existing_ code                        |
| Responsive/A11y            | +3    | "responsive"/"a11y" in PR, not in ticket          |                                                            |
| Performance optimization   | +3    | "optimization"/"performance" in PR, not in ticket |                                                            |
| Type/Lint improvements     | +2    | "typefix"/"eslint" in PR, not in ticket           |                                                            |
| Validation logic           | +2    | "validation" in PR, not in ticket                 |                                                            |
| Developer Experience (DX)  | +2    | "chore(DX)" in PR title                           |                                                            |
| Bug fixes (non-bug ticket) | +2    | 5+ fix commits on non-bug/fix ticket              | Threshold increased: assumes most fixes are self-inflicted |

**Your Common Bonus Work Patterns:**

- **"chore(DX)"** PRs often include testing, linting, and type improvements not in original scope
- **Responsive work** frequently added during feature implementation (not in ticket)
- **"yeeting"** legacy/unused code while implementing features (cleanup beyond scope)
- **TypeScript/ESLint fixes** bundled with features (quality improvement)

**Important Distinctions:**

✅ **Bonus work:**

- Adding tests when ticket says "implement feature X" (no mention of testing)
- Making feature responsive when ticket doesn't require it
- Refactoring _existing/legacy_ code while adding feature
- Fixing 5+ existing/unrelated bugs during feature implementation
- "yeeting" old/unused code while implementing feature

❌ **Not bonus (natural iteration):**

- "yeeting" code you added 3 commits ago (exploration)
- Refactoring your own new code to get it right (refinement)
- Fixing bugs you introduced during implementation (getting feature to work)
- Most "fix" commits within a PR (likely self-inflicted)

The script detects bonus work by comparing PR/commit keywords against JIRA description, summary, and type.

**Detection Logic:**

1. **Explicit mention**: If JIRA description says "add tests" → tests are NOT bonus
2. **Implied by ticket type**: If ticket type is "Bug" → testing is IMPLIED → tests are NOT bonus
3. **Implied by context**: If ticket mentions "migration" → testing/refactoring are IMPLIED → NOT bonus
4. **Beyond scope**: If ticket says "implement feature X" (no testing mentioned, not a bug) → tests ARE bonus

**Examples of Implied Work (from 46 real tickets):**

| Ticket Summary Pattern                   | Issue Type | Implied Work                     | Reasoning                                        |
| ---------------------------------------- | ---------- | -------------------------------- | ------------------------------------------------ |
| "Endpoint config - cannot edit..."       | Bug        | Testing                          | Bug fixes require validation                     |
| "ESLint flat config migration..."        | Task       | Testing, refactoring, type fixes | Migrations imply comprehensive work              |
| "chore(DX): Consolidate..."              | Task       | Refactoring, cleanup, testing    | DX tickets are about code quality                |
| "Replace MUI Snackbar..."                | Task       | Refactoring, testing             | Replacements need validation                     |
| "Remove old sidenav..."                  | Task       | Cleanup, refactoring, testing    | Removals need validation                         |
| "Add validation logic..."                | Task       | Validation, testing              | Validation tickets imply testing                 |
| "Update Methods ... responsive behavior" | Task       | Responsive design                | Explicitly mentioned                             |
| "Create preview view..."                 | UI Task    | (minimal)                        | "Create" UI tasks don't imply testing/responsive |
| "Add functionality to..."                | Task       | (minimal)                        | Simple adds don't imply extras                   |

**Warning Output:** The script shows ⚠️ for work that was detected but NOT counted as bonus because it's implied:

```
⚠️  Testing added (but implied by ticket type: Bug)
⚠️  Type/lint improvements (but implied by DX ticket)
```

**Interpretation:**

- **0**: Scope aligns with ticket
- **1-5**: Minor bonus work (e.g., validation, type fixes)
- **6-10**: Moderate bonus work (e.g., testing + refactoring)
- **11-15**: Significant scope expansion (e.g., responsive + tests + cleanup)
- **15+**: Major bonus work (e.g., DX improvement with migration + refactor + comprehensive testing)

### 5. Composite Effort Score

**Formula:**

```
Composite = (Adjusted Days × 10) + Commit Complexity + PR Complexity + (Bonus Work × 2)
```

**Effort Levels:**

- **< 30**: Low (simple, straightforward)
- **30-79**: Medium (moderate complexity, some investigation)
- **80-149**: High (complex work, significant debugging/refactoring)
- **150+**: Very High (extensive effort, major complexity)

**Example Calculation:**

```
Adjusted Days:        8.0
Commit Complexity:   45
PR Complexity:       12
Bonus Work:           8

Composite = (8.0 × 10) + 45 + 12 + (8 × 2)
          = 80 + 45 + 12 + 16
          = 153 (Very High)
```

## Output Format

### Console Output

Human-readable report with sections:

- 📋 PR Details
- ⏱️ Base Timeline
- 🔄 Concurrent PR Activity
- 💬 Commit Message Analysis
- 📝 PR Description Analysis
- 🎯 Scope Analysis (JIRA vs PR)
- 📊 Effort Summary with composite score and effort level

### JSON Output

Structured data suitable for:

- Integration with brag doc generation pipeline
- Aggregation across multiple PRs
- Further analysis or visualization

**Schema:**

```json
{
  "pr_number": "1234",
  "repo": "kasada-io/kasada",
  "title": "Implement feature X",
  "jira_ticket": "VIS-123",
  "timeline": {
    "base_days": 10.5,
    "adjusted_days": 8.0
  },
  "complexity": {
    "commit_count": 42,
    "commit_complexity_score": 45,
    "pr_description_complexity": 12
  },
  "bonus_work_score": 8,
  "composite_effort_score": 153,
  "effort_level": "Very High",
  "effort_description": "Extensive effort with major complexity, investigation, or bonus work"
}
```

## Dependencies

Requires:

- Populated GitHub database (`.cache/github_report.db`)
- Populated JIRA database (`.cache/jira_tickets.db`) for scope comparison
- `jq` for JSON processing
- `bc` for floating-point arithmetic

## Integration with Brag Doc Pipeline

### Option 1: Enrich Existing Brag Items

After generating brag doc items, run effort analysis and merge results:

```bash
# Generate brag doc for December 2025
./steps/01_query_database.sh 2025-12-01 2026-01-01

# Analyze PR efforts
./github-summary/scripts/analysis/batch_analyze_efforts.sh kasada-io/kasada 2025-12-01 2026-01-01

# Merge effort data into brag items (custom script needed)
```

### Option 2: Real-time Enrichment

Modify `steps/04_enrich_metadata.sh` to call `analyze_pr_effort.sh` for each PR and inject effort metrics.

### Option 3: LLM Context

Include effort analysis JSON output when prompting LLM for achievement interpretation:

```bash
# Pass effort analysis as additional context
cat pr_effort_analysis.json | jq '.' | \
  ./steps/03a_llm_achievements.sh month-data.json
```

## Limitations & Future Improvements

### Current Limitations

1. **Concurrent PR adjustment is simplified**: Uses 50% split regardless of actual time distribution
2. **Keyword detection is basic**: Simple grep patterns, no semantic analysis
3. **No code diff analysis**: Doesn't examine lines changed, files touched, or code complexity
4. **Weekend exclusion only**: Doesn't account for holidays or PTO
5. **Single-author assumption**: Doesn't attribute effort for multi-author PRs

### Potential Enhancements

1. **Smarter concurrent work detection**: Use commit timestamps and sizes to better allocate effort
2. **Code complexity metrics**: Analyze cyclomatic complexity, lines changed, files touched
3. **Semantic text analysis**: Use LLM to extract effort signals from descriptions
4. **Holiday/PTO integration**: Read from calendar data to exclude non-working days
5. **Multi-author attribution**: Split effort based on commit authorship
6. **Review effort tracking**: Analyze review comments and iterations
7. **External dependency detection**: Flag PRs blocked by other teams or external factors

## Tuning the Formula

If the effort scores don't match your intuition, adjust the weights:

**In `analyze_pr_effort.sh`, line ~330:**

```bash
composite_score=$(echo "scale=0; ($adjusted_days * 10) + $complexity_score + $pr_complexity + ($bonus_work_score * 2)" | bc)
```

**Example adjustments:**

- **Emphasize timeline over complexity**: Increase multiplier on `adjusted_days` (e.g., ×15)
- **Emphasize bonus work**: Increase multiplier on `bonus_work_score` (e.g., ×3)
- **Add commit count weight**: `+ ($commit_count * 0.5)`

**Effort level thresholds (line ~337):**

```bash
if [ "$composite_score" -lt 30 ]; then
  effort_level="Low"
elif [ "$composite_score" -lt 80 ]; then
  effort_level="Medium"
...
```

Adjust these breakpoints based on your team's typical PR sizes and complexity.

## Example Scenarios

### Scenario 1: Simple Feature (Low Effort)

**Context:**

- 2 business days open
- 5 commits, straightforward messages
- Brief PR description
- Work matches ticket exactly

**Scores:**

- Adjusted days: 2.0
- Commit complexity: 4
- PR complexity: 2
- Bonus work: 0
- **Composite: 26 (Low)**

---

### Scenario 2: Complex Bug Fix (High Effort)

**Context:**

- 5 business days, 2 days overlapping with other PR
- 18 commits with multiple "debug", "investigate", "fix" messages
- Detailed PR description with risk callouts and testing notes
- Fixed 3 related bugs not in original ticket

**Scores:**

- Adjusted days: 4.0 (5 - 2×0.5)
- Commit complexity: 38
- PR complexity: 11
- Bonus work: 2 (bug fixing)
- **Composite: 93 (High)**

---

### Scenario 3: Large Refactor with Scope Expansion (Very High Effort)

**Context:**

- 12 business days, 4 days overlapping
- 56 commits with extensive refactoring, testing, and optimization
- Comprehensive PR description with architecture discussion
- Added tests, documentation, performance optimization (not in ticket)

**Scores:**

- Adjusted days: 10.0 (12 - 4×0.5)
- Commit complexity: 64
- PR complexity: 18
- Bonus work: 11 (refactor + tests + docs + performance)
- **Composite: 204 (Very High)**

---

## Questions or Issues?

If the scores seem off or you'd like to tune the heuristics, look at:

1. The keyword lists (lines ~170-180 for commits, ~300-350 for bonus work)
2. The composite score formula (line ~330)
3. The effort level thresholds (lines ~337-348)

These are designed as reasonable starting heuristics but should be calibrated to your team's patterns over time.
