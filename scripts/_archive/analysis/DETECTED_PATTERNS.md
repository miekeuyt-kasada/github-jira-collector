# Your Detected Writing Patterns

This document shows the patterns extracted from your actual PR descriptions and commit messages. The effort analysis
script has been customized to recognize your specific language and documentation style.

## Commit Message Patterns

### What I Analyzed

- 62 PRs from your GitHub database
- 100+ recent commit messages
- Focus on PRs from 2025 (most recent patterns)

### Patterns Detected & Weight

#### High-Effort Indicators (×3 weight)

- **"PR feedback"** / **"PR commento"** / **"coderabbit"**
  - Indicates review iteration cycles
  - Example: `"prev PR feedback: yeet useless memo and run clean on alert registry component"`
  - **Why it matters**: Multiple review cycles = higher effort

#### Medium-Effort Indicators (×2 weight)

- **"wip"** / **"ugly implem"** / **"basic implem"** / **"tempfix"**
  - Iterative work, indicates ongoing refinement
  - Example: `"ugly implem"` → `"basic implem"` → `"proper implem"`
  - **Signal**: Multiple attempts = exploration effort

#### Standard Indicators (×1 weight)

- **"fix"** / **"bugfix"** / **"oopsie"**
  - Bug fixing work (but often just fixing bugs introduced during implementation)
  - Example: `"fix and test"`, `"bugfix and extra test"`
  - **Caveat**: If fixing bugs you just introduced = natural iteration, not extra effort
  - **Bonus work**: Only if fixing _existing/unrelated_ bugs
- **"refactor"** / **"cleanup"** / **"cleaner"** / **"clean"**
  - Code quality work (but might be natural iteration within PR)
  - Example: `"refactor/clean"`
  - **Caveat**: Only counts as bonus work if refactoring code _outside_ the ticket scope
- **"yeeting"**
  - Your term for removing/deleting code
  - Example: `"yeeting unnecessary commented out and temp disabled"`
  - Example: `"yeeting the accidentally readded memo"`
  - **Caveat**: If yeeting code added in same PR = iteration, not extra effort
  - **Bonus work**: Only if yeeting legacy/unrelated code
- **"test"** / **"testing suite"**
  - Example: `"adding tests"`, `"testing suite implem"`
- **"typefix"** / **"type fix"** / **"eslint"**
  - TypeScript and linting work
  - Example: `"typefix"`, `"minor typefix"`
- **"responsive"** / **"aria"** / **"a11y"**
  - Accessibility and responsive design
  - Example: `"making responsive"`, `"fix aria-hidden"`
- **"implem"** (not "implement")
  - Your shortened form
  - Often paired with qualifiers: "basic implem", "ugly implem", "proper implem"

### Phrases NOT Commonly Used

These generic patterns don't appear in your commit messages:

- ❌ "investigate"
- ❌ "explore"
- ❌ "research"
- ❌ "spike"
- ❌ "debug" (you use "fix" instead)
- ❌ "improve" (you use "cleanup"/"refactor" instead)

## PR Description Patterns

### Structure You Use

#### For Complex PRs (6000+ chars)

Example: ESLint migration PR

**Pattern:**

```markdown
# [TICKET] Summary

<Brief overview>

## 🔑 Key points of interest

<Important callouts>

##### Phase 1: <Category>

<commit SHA> - <description> <commit SHA> - <description>

##### Phase 2: <Category>

<commit SHA> - <description>

#### Code Fixes Applied

- <fix description> (<commit SHA>)

#### Dependency Changes

##### Added

- package@version

##### Removed

- package@version

##### Updated

- package: old → new
```

**Detection triggers:**

- Phased breakdowns with "Phase 1:", "##### Phase"
- Commit-by-commit changelog
- Commit SHAs referenced (40-char hashes)
- Dependency change sections
- "## 🔑 Key points of interest"

#### For Medium PRs (1500-3000 chars)

- Summary section
- Lists of changes
- JIRA ticket link
- Maybe sections for "Why" or "How"

#### For Small PRs (< 1000 chars)

- Brief summary
- JIRA ticket link
- Sometimes just 1-2 sentences

### Prefixes You Use

From your PR titles:

- **`chore(DX):`** - Developer experience improvements
  - ESLint, tooling, build config
  - Often includes bonus work (tests, types, cleanup)
- **`feat(component):`** - Feature work
  - Example: `feat(verified-bots):`, `feat(endpoint-config):`
- **`fix(component):`** - Bug fixes
  - Example: `fix(endpoint-config):`, `fix(e2e test):`
- **`chore(component):`** - Maintenance work
  - Example: `chore(verified-bots):`, `chore(registry-component-update):`

## Bonus Work Patterns

Work types you commonly add beyond ticket scope:

**Important nuances**: Distinguishes between:

- **Iteration within PR scope** (add → yeet → add) = not bonus work
- **Work implied by ticket** (testing on bug fix, refactoring on migration) = not bonus work
- **Work beyond ticket scope** (adding tests to simple feature, making it responsive when not mentioned) = bonus work

### Very Common (+3 each)

1. **Testing** - "adding tests", "test" (when NOT in ticket AND NOT implied by ticket type)
2. **Refactoring** - "refactor", "cleanup" of _existing/legacy code_ (when NOT implied by chore/migration ticket)
3. **Responsive/A11y** - "making responsive", "fix aria" (when NOT mentioned or implied in ticket)

### Common (+2 each)

4. **Type improvements** - "typefix", "eslint" fixes
5. **Validation logic** - "adding validation"
6. **DX improvements** - `chore(DX):` PRs
7. **Bug fixes of existing bugs** - 5+ "fix" commits on non-bug tickets (suggests fixing unrelated/existing bugs)

### Occasional (+4)

8. **Migration** - Major refactors like ESLint v8→v9

## Examples from Your Actual Work

### High Effort PR (ESLint Migration)

**Signals detected:**

- 6211 char description with phases
- 30+ commit SHAs referenced
- Dependency changes section
- 56 commits over 12 days
- Extensive refactoring + cleanup + testing
- **Estimated composite score: ~180 (Very High)**

### Medium Effort PR (Feature with Testing)

**Signals detected:**

- 2500 char description
- "adding tests" commits not in ticket
- "cleanup based on coderabbit nitpicks" (PR iteration)
- Responsive improvements added
- **Estimated composite score: ~75 (Medium-High)**

### Low Effort PR (Simple Fix)

**Signals detected:**

- < 800 char description
- 3-5 commits, straightforward messages
- Single focused fix
- **Estimated composite score: ~25 (Low)**

## Tuning Recommendations

The script is now calibrated to your patterns, but you can fine-tune:

### If Scores Feel Too High

Reduce these in `analyze_pr_effort.sh`:

```bash
# Line ~180: Reduce iteration weight
iteration_count * 3  →  iteration_count * 2

# Line ~330: Reduce timeline multiplier
adjusted_days * 10  →  adjusted_days * 8
```

### If Scores Feel Too Low

Increase these:

```bash
# Line ~180: Increase refactor weight
refactor_count * 2  →  refactor_count * 3

# Line ~240+: Increase PR description scores
has_phases = +8  →  has_phases = +10
```

### If "Yeeting" Should Count More

It's a unique pattern indicating cleanup work:

```bash
# Add dedicated counter around line ~170
yeet_count=$(echo "$commit_messages" | grep -ci "yeet" || echo "0")
complexity_score=$((... + yeet_count * 2))
```

## Next Steps

1. **Test on a few PRs** to see if scores match your intuition:

   ```bash
   ./analyze_pr_effort.sh kasada-io/kasada 1863  # ESLint PR
   ./analyze_pr_effort.sh kasada-io/kasada 1849  # Simple PR
   ```

2. **Compare scores** - Do high-effort PRs score higher than simple ones?

3. **Adjust weights** if needed (see Tuning Recommendations above)

4. **Add new patterns** as you notice them in future work

## Pattern Evolution

Your patterns as of January 2025. If your writing style changes (new team conventions, different project phases), re-run
the pattern detection:

```bash
# Re-analyze recent commits
sqlite3 github-summary/scripts/.cache/github_report.db \
  "SELECT message FROM pr_commits WHERE date > '2025-06-01' ORDER BY date DESC LIMIT 200"
```

Look for:

- New keywords that appear frequently
- Changes in how you structure PR descriptions
- New types of bonus work you're adding

Then update the script keywords accordingly.
