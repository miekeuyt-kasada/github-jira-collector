# PR Effort Analysis - Changelog

## v1.2 - Data-Driven Implied Work Detection (Current)

### What Changed

Analyzed 46 real JIRA tickets from your database to identify actual patterns and implied work, replacing generic
assumptions with data-driven detection.

### Key Improvements

#### 1. JIRA Pattern Analysis

- Created `JIRA_PATTERNS_ANALYSIS.md` documenting real ticket patterns
- Analyzed ticket type distribution: 50% Task, 22% UI Task, 15% Bug, etc.
- Identified action verb patterns: Create, Update, Add, Replace, Remove
- Found keyword patterns that imply specific work types

#### 2. Refined Implied Work Detection

**Testing is IMPLIED for:**

- ✅ Bug fixes (all 7 bugs analyzed)
- ✅ "Replace..." tickets (e.g., "Replace MUI Snackbar with toasts")
- ✅ "Remove..." tickets (e.g., "Remove old sidenav...")
- ✅ Validation tickets (e.g., "Add validation logic...")
- ✅ Migration tickets (e.g., "ESLint flat config migration")

**Testing is NOT implied for:**

- ❌ "Create..." UI tasks (e.g., "Create preview view...")
- ❌ "Add functionality..." tickets (unless testing explicitly mentioned)
- ❌ Simple "Update..." tickets (unless "Update tests")

**Refactoring is IMPLIED for:**

- ✅ chore(DX) tickets
- ✅ "Replace..." tickets
- ✅ "Remove..." tickets
- ✅ Migration tickets
- ✅ "Consolidate..." / DRY tickets

**Responsive work is IMPLIED for:**

- ✅ ONLY when explicitly mentioned (e.g., "Update Methods ... responsive behavior")
- ❌ NOT implied for general UI tasks

**Type/lint is IMPLIED for:**

- ✅ chore(DX) tickets
- ✅ ESLint/TypeScript tickets
- ✅ Migration tickets

#### 3. Detection Logic Updates

**Before:** Generic keyword matching  
**After:** Pattern-based matching using real ticket summaries

```bash
# Old (generic)
if ticket has "bug" → testing implied

# New (specific)
if issue_type = "Bug" OR
   summary starts with "Replace " OR
   summary starts with "Remove " OR
   summary contains "migrat" OR
   summary contains "validat" → testing implied
```

### Real Examples

**Example 1: UI Task - Testing IS Bonus**

- Ticket: "Create preview view for Verified Bot settings page"
- Type: UI Task
- Pattern: "Create..."
- **Result**: Testing IS bonus work (not implied for simple Create tasks)

**Example 2: Replace Task - Testing NOT Bonus**

- Ticket: "Replace MUI Snackbar notifications with toasts"
- Type: Task
- Pattern: "Replace..."
- **Result**: Testing NOT bonus (implied for replacements)

**Example 3: Migration - Nothing is Bonus**

- Ticket: "ESLint flat config migration 8 -> 9"
- Type: Task
- Pattern: "migration"
- **Result**: Testing, refactoring, type fixes all NOT bonus (comprehensive work implied)

---

## v1.1 - Natural Iteration Recognition

### What Changed

Refined weighting to account for natural iteration within PR scope, based on user feedback.

### Key Changes

1. **Reduced weights for fix/refactor/yeeting**

   - "fix" commits: ×2 → ×1 (often self-inflicted bugs)
   - "refactor" commits: ×2 → ×1 (often refining own code)
   - "yeeting" commits: ×2 → ×1 (often removing own code)

2. **Increased bonus work threshold**

   - Bug fixes: 4+ → 5+ commits to count as bonus
   - Reasoning: Most fixes are self-inflicted

3. **Clarified bonus work vs iteration**
   - ✅ Bonus: Refactoring _existing/legacy_ code
   - ❌ Not bonus: Refactoring your own new code
   - ✅ Bonus: Fixing 5+ _existing_ bugs
   - ❌ Not bonus: Fixing bugs you just introduced

---

## v1.0 - Initial Release

### Features

1. **Timeline Adjustment**

   - PR duration excluding weekends
   - Adjustment for concurrent PR work (days with commits on other PRs)

2. **Commit Complexity**

   - Customized patterns for Mieke's vocabulary
   - "yeeting", "PR commento", "implem", etc.
   - Weighted scoring based on effort indicators

3. **PR Description Analysis**

   - Detects phased breakdowns
   - Commit-by-commit changelogs
   - Dependency changes sections
   - Length-based complexity scoring

4. **Basic Bonus Work Detection**
   - Keyword comparison (PR vs JIRA description)
   - Simple implied work detection

### Pattern Detection

Analyzed 62 PRs and 100+ commit messages to identify:

- "PR commento" / "PR feedback" (review cycles)
- "wip" / "ugly implem" / "basic implem" (iteration)
- "yeeting" (code removal)
- "implem" (not "implement")
- "oopsie" (bugs)
- "cleanup" / "refactor"
- "typefix" / "eslint"

---

## Upgrade Path

If you're using an older version:

### From v1.1 → v1.2

- No breaking changes
- Implied work detection is now more accurate
- Bonus work scores may decrease (more work flagged as implied)
- Review `JIRA_PATTERNS_ANALYSIS.md` to understand new logic

### From v1.0 → v1.2

- Commit complexity scores will decrease (lower weights for fix/refactor)
- Bonus work threshold increased (5+ fixes instead of 4+)
- More work flagged as implied (especially for chore(DX), Replace, Remove tickets)
- Review both `DETECTED_PATTERNS.md` and `JIRA_PATTERNS_ANALYSIS.md`

---

## Future Improvements

Potential enhancements based on usage patterns:

1. **Code diff analysis** - Lines changed, cyclomatic complexity
2. **Blocked time detection** - PRs waiting on external dependencies
3. **Review effort tracking** - Time spent reviewing others' PRs
4. **Multi-author attribution** - Split effort for pair programming
5. **Holiday/PTO exclusion** - Beyond weekend filtering
6. **Semantic text analysis** - LLM-based effort signal extraction
7. **Historical calibration** - Auto-tune weights based on PR outcomes
