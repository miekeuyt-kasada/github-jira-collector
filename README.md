# GitHub + Jira Collector

A shell-based toolkit for collecting GitHub activity (PRs, commits) and enriching it with Jira metadata. Built around SQLite caching to minimize API calls and support historical analysis.

## What It Does

1. **Fetches GitHub data**: PRs and commits for a given user across all their repositories
2. **Caches intelligently**: Stores everything in SQLite with smart TTL logic (closed PRs cached forever, open PRs refetched)
3. **Generates reports**: Markdown summaries showing activity by repo, PR state, and commit history
4. **Enriches with Jira** _(optional)_: Links PRs to Jira tickets, tracks status history, calculates blocked time

## Quick Start

### Prerequisites

- **GitHub CLI** (`gh`) — [install](https://cli.github.com/)
- **SQLite** (usually pre-installed on macOS/Linux)
- **jq** — `brew install jq` or `apt-get install jq`
- **Authenticated** — Run `gh auth login` first

### Environment Setup

Create `.env.local` in the project root:

```bash
# Required for GitHub
GITHUB_USERNAME=your-github-username

# Optional - for JIRA enrichment
JIRA_EMAIL=your-email@domain.com
JIRA_API_TOKEN=your-jira-token
JIRA_BASE_URL=https://your-org.atlassian.net
```

Get JIRA API token: <https://id.atlassian.com/manage-profile/security/api-tokens>

### Basic Usage

```bash
cd lib

# 1. Fetch GitHub data (uses GITHUB_USERNAME from .env.local)
./get_github_data.sh 6                                    # Last 6 months
./get_github_data.sh --username other-user 6              # Or explicit username
./get_github_data.sh 2025-07-01 2025-12-31                # Date range

# 2. Fetch JIRA data (enriches PRs with ticket metadata)
./get_jira_data.sh                                        # Fetches all tickets from PRs
./get_jira_data.sh --limit 10                             # Test with 10 tickets

# 3. Generate markdown report
./generate_report.sh 2025-08-01 2026-02-01                # Uses GITHUB_USERNAME
./generate_report.sh --username other-user 2025-08-01 2026-02-01

# 4. Query data as JSON
./database/query_month_data.sh 2025-08-01 2026-02-01      # GitHub data
./database/query_jira_data.sh --epic VIS-98               # JIRA data by epic
```

**Output**: `generated/your-username-commits-2025-08-01_2026-02-01.md`

### Force Refresh

```bash
# Clear repo cache and refetch everything
./get_github_data.sh -f 6

# Force refresh JIRA data (ignores cache)
./get_jira_data.sh --force
```

---

## How It Works

### 1. Repository Discovery

Script: `api/fetch_repos.sh`

Finds all repos where the user has contributed:

- Personal repos (via `gh repo list`)
- Organization repos (e.g., `kasada/*`) where user is a contributor
- Filters out archived, empty, or inactive repos

**Caching**: Repos are cached per user + `since_date`. Superset logic applies — if you cached repos since June, a query for August reuses that cache (repos don't retroactively appear in earlier periods).

### 2. PR & Commit Collection

Scripts: `api/get_prs.sh`, `api/get_pr_commits.sh`, `api/get_direct_commits.sh`

For each repo:

- Fetch all PRs authored by user
- Fetch commits within each PR
- Fetch direct commits (not part of any PR)

**Caching**:

- **Closed/merged PRs**: Cached permanently (state won't change)
- **Open/draft PRs**: Always refetched (might have new commits or state transitions)

### 3. Pre-computed Metrics

The database stores computed values to avoid recalculation:

| Field | Description |
|-------|-------------|
| `duration_seconds` | PR lifetime (opened → closed/merged), **weekends excluded** |
| `duration_formatted` | Human-readable (e.g., "3d 5h 12m") |
| `commit_span_seconds` | First commit → last commit, **weekends excluded** |
| `commit_span_formatted` | Human-readable commit span |
| `state_pretty` | MERGED / CLOSED / OPEN |
| `is_ongoing` | Boolean flag for open PRs |
| `jira_ticket` | Extracted ticket key (e.g., VIS-454, CORS-3342) |

**Business days logic**: All durations exclude Saturday and Sunday. A PR opened Friday 5pm and closed Monday 9am shows ~2 hours of duration, not ~63 hours.

### 4. Report Generation

Script: `generate_report.sh`

Reads from the SQLite cache and produces a structured markdown file:

- Grouped by repository
- Sections for PRs and direct commits
- Shows PR state, duration, description, and commit history
- Links to GitHub for easy navigation

---

## Jira Integration _(Optional)_

If you work with Jira, the toolkit can:

- Extract Jira ticket keys from PR titles/branches
- Fetch ticket metadata (status, epic, assignee, story points, custom fields)
- Track status history (when did it move to "Done"? how long was it blocked?)
- Cache tickets with smart TTL (closed = forever, open = 24h)

### Setup

See [`lib/JIRA_INTEGRATION.md`](lib/JIRA_INTEGRATION.md) for full details.

**TL;DR:**

1. Create a Jira API token: <https://id.atlassian.com/manage-profile/security/api-tokens>
2. Configure `.env.local`:

```bash
JIRA_EMAIL=you@example.com
JIRA_API_TOKEN=your-token
JIRA_BASE_URL=https://your-org.atlassian.net
```

1. Source and export:

```bash
source .env.local
export JIRA_EMAIL JIRA_API_TOKEN JIRA_BASE_URL
```

1. Fetch tickets:

```bash
# Fetch all tickets referenced in GitHub PRs
./lib/get_jira_data.sh

# Or fetch a specific ticket
./lib/api/get_jira_ticket.sh VIS-454

# View statistics
./lib/api/show_jira_stats.sh
```

### Jira Custom Fields

Jira instances use different custom field IDs. Run the discovery script to find yours:

```bash
./lib/api/discover_jira_fields.sh
```

Add the relevant field IDs to `.env.local` (see [`lib/JIRA_INTEGRATION.md`](lib/JIRA_INTEGRATION.md) for examples).

---

## Architecture

```
lib/
├── get_github_data.sh          # Main entry: fetch & cache GitHub data
├── generate_report.sh          # Generate markdown from cached data
├── utils.sh                    # Date/duration helpers (business days logic)
│
├── api/
│   ├── fetch_repos.sh                  # Discover repos with user contributions
│   ├── get_prs.sh                      # Fetch PRs for a repo
│   ├── get_pr_commits.sh               # Fetch commits within PRs
│   ├── get_direct_commits.sh           # Fetch commits not in PRs
│   ├── get_jira_ticket.sh              # Fetch single Jira ticket metadata
│   ├── fetch_all_github_tickets.sh     # Batch fetch all tickets from GitHub PRs
│   ├── discover_jira_fields.sh         # Find custom field IDs
│   ├── harvest_jira_custom_fields.sh   # Harvest all custom fields (using API token)
│   ├── harvest_jira_with_cookies.sh    # Harvest custom fields (using browser cookies)
│   └── show_jira_stats.sh              # Display statistics about cached Jira tickets
│
├── database/
│   ├── db_init.sh              # Initialize GitHub cache DB
│   ├── db_helpers.sh           # Cache queries and helpers
│   ├── jira_init.sh            # Initialize Jira cache DB
│   └── jira_helpers.sh         # Jira cache queries
│
└── .cache/
    ├── github_data.db          # SQLite: PRs, commits, repos
    └── jira_tickets.db         # SQLite: Jira tickets & history
```

### Database Schema

#### `github_data.db`

**prs**

- `repo`, `pr_number`, `title`, `state`, `draft`, `merged_at`
- `duration_seconds`, `duration_formatted` (business days)
- `commit_span_seconds`, `commit_span_formatted` (first → last commit)
- `jira_ticket` (extracted from title/branch)

**pr_commits**

- `repo`, `pr_number`, `sha`, `author`, `date`, `message`

**direct_commits**

- `repo`, `sha`, `author`, `date`, `message`

**repos**

- `username`, `since_date`, `repo_name`, `fetched_at`

#### `jira_tickets.db`

**jira_tickets**

- `ticket_key`, `summary`, `status`, `issue_type`, `assignee`, `priority`
- `epic_key`, `epic_name`, `story_points`, `chapter`, `service`, `capex_opex`
- `is_closed` (determines cache TTL)

**jira_ticket_history**

- `ticket_key`, `field_name`, `old_value`, `new_value`, `changed_at`, `changed_by`

---

## Common Workflows

### Monthly Activity Report

```bash
cd lib
./get_github_data.sh miekeuyt 2025-12-01 2026-01-01
./generate_report.sh miekeuyt 2025-12-01 2026-01-01
```

### Cross-reference PRs with Jira

```bash
# View PRs grouped by Jira ticket
sqlite3 lib/.cache/github_data.db \
  "SELECT jira_ticket, COUNT(*) as pr_count 
   FROM prs 
   WHERE jira_ticket IS NOT NULL 
   GROUP BY jira_ticket;"

# View Jira ticket statistics
./lib/api/show_jira_stats.sh
```

### Analyze PR Duration

```bash
# Show PRs with longest durations (business days)
sqlite3 lib/.cache/github_data.db \
  "SELECT pr_number, title, duration_formatted 
   FROM prs 
   WHERE state_pretty = 'MERGED' 
   ORDER BY duration_seconds DESC 
   LIMIT 10;"
```

### Inspect Jira Status Changes

```bash
# Get status history for a ticket
sqlite3 lib/.cache/jira_tickets.db \
  "SELECT changed_at, old_value, new_value 
   FROM jira_ticket_history 
   WHERE ticket_key = 'VIS-454' 
     AND field_name = 'status' 
   ORDER BY changed_at;"
```

### Jira Utility Scripts

```bash
# View cached Jira ticket statistics (by status, type, epic, etc.)
./lib/api/show_jira_stats.sh

# Fetch all tickets referenced in GitHub PRs (batched)
./lib/api/fetch_all_github_tickets.sh

# Harvest custom field data from Jira API
./lib/api/harvest_jira_custom_fields.sh

# Alternative: Harvest using browser cookies (when API token insufficient)
export JIRA_COOKIES='your-browser-cookies'
./lib/api/harvest_jira_with_cookies.sh
```

---

## Cache Behavior

### Why Cache?

- **Speed**: 10-50× faster on repeated runs
- **API limits**: GitHub rate limits are ~5000 req/hour; Jira varies by tier
- **Consistency**: Pre-computed stats ensure identical formatting across runs
- **Historical analysis**: Query across time periods without re-fetching

### Cache Invalidation

| Data Type | Cache Strategy |
|-----------|----------------|
| **Repo lists** | Permanent (superset logic: wider date ranges cover narrower ones) |
| **Closed PRs** | Permanent (state won't change) |
| **Open PRs** | Refetched on every run (might have new commits/state) |
| **Closed Jira tickets** | Permanent (status = Done/Resolved/Closed) |
| **Open Jira tickets** | TTL = 24 hours |
| **Jira history** | Permanent for closed tickets, refetched for open ones |

### Clear Cache

```bash
# Clear GitHub cache
rm lib/.cache/github_data.db

# Clear Jira cache
rm lib/.cache/jira_tickets.db
```

---

## Testing

Uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

```bash
# Install BATS (macOS)
brew install bats-core

# Run all tests
cd tests
bats unit/

# Run specific test file
bats unit/utils.bats
```

Test coverage:

- `utils.bats` — Date parsing, duration formatting, business days logic
- `db_helpers.bats` — Cache queries, repo superset logic
- `jira_helpers.bats` — Jira caching, history queries

---

## Configuration

### Environment Variables

#### GitHub (Required)

Set via `gh auth login` — no manual config needed.

#### Jira (Optional)

```bash
JIRA_EMAIL                # Your Atlassian account email
JIRA_API_TOKEN            # API token from id.atlassian.com
JIRA_BASE_URL             # e.g., https://yourorg.atlassian.net
```

#### Jira Custom Fields (Optional — will auto-discover if missing)

```bash
JIRA_EPIC_FIELD           # Epic Link (default: customfield_10009)
JIRA_EPIC_NAME_FIELD      # Epic Name (default: customfield_10008)
JIRA_SPRINT_FIELD         # Sprint (default: customfield_10007)
JIRA_STORY_POINTS_FIELD   # Story Points (default: customfield_11004)
JIRA_CHAPTER_FIELD        # Chapter primary (default: customfield_11782)
JIRA_CHAPTER_ALT_FIELD    # Chapter alternative (default: customfield_12384)
JIRA_SERVICE_FIELD        # Service primary (default: customfield_11783)
JIRA_SERVICE_ALT_FIELD    # Service alternative (default: customfield_12383)
JIRA_CAPEX_OPEX_FIELD     # CAPEX vs OPEX (default: customfield_11280)
```

### `.env.local` Example

```bash
# GitHub (handled by gh CLI)
GITHUB_USERNAME=miekeuyt

# Jira
JIRA_EMAIL=you@example.com
JIRA_API_TOKEN=ATATT3xFfGF0...
JIRA_BASE_URL=https://yourorg.atlassian.net

# Jira custom fields (run discover_jira_fields.sh to find these)
JIRA_EPIC_FIELD=customfield_10009
JIRA_EPIC_NAME_FIELD=customfield_10008
JIRA_SPRINT_FIELD=customfield_10007
JIRA_STORY_POINTS_FIELD=customfield_11004
```

---

## Troubleshooting

### "gh: command not found"

Install GitHub CLI: <https://cli.github.com/>

### "gh: not authenticated"

```bash
gh auth login
```

### "Database not found"

Run `./get_github_data.sh` first to initialize and populate the cache.

### "No data found in database for date range"

Either:

- You have no activity in that range (check with `gh pr list --author @me`)
- Cache is empty for those dates — run `./get_github_data.sh` first

### Jira Authentication Fails

```bash
# Test your credentials manually
curl -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_BASE_URL/rest/api/3/myself"
```

If this fails, regenerate your API token: <https://id.atlassian.com/manage-profile/security/api-tokens>

### Epic field not found

Jira instances vary — run the discovery script:

```bash
./lib/api/discover_jira_fields.sh
```

Look for fields named "Epic Link", "Epic Name", etc., and update `.env.local`.

### Custom field discovery

If you need to find all custom fields used in your tickets:

```bash
# Using API token
./lib/api/harvest_jira_custom_fields.sh

# If API token has insufficient permissions, use browser cookies
# 1. Open Jira in browser
# 2. Open DevTools (F12) → Network tab
# 3. Copy cookies from any request (Copy as cURL)
# 4. Export the cookie string:
export JIRA_COOKIES='your-cookie-string'
./lib/api/harvest_jira_with_cookies.sh
```

This analyzes all tickets referenced in your GitHub PRs and shows which custom fields contain data.

---

## Further Reading

- **[lib/JIRA_INTEGRATION.md](lib/JIRA_INTEGRATION.md)** — Jira setup, API details, helper functions

---

## Contributing

This is a personal toolkit, but PRs welcome.
