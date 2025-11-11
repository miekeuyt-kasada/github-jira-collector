# GitHub Report Cache

## Overview

The report generation scripts use SQLite to cache repository lists, PR data, and commit data, dramatically reducing
GitHub API calls on repeated runs.

## Database Location

`.cache/github_report.db` (automatically created, gitignored)

## Cache Strategy

### Repository List Caching

Repository lists are cached with **interval-based superset logic**:

- Repos are cached by username and `since_date` (e.g., "2025-06-11")
- If you request repos since "2025-08-01" but have cached repos since "2025-06-01", the cache is used (wider interval
  covers narrower one)
- Repos won't retroactively appear in earlier time periods, so older caches remain valid for newer queries
- Cache is permanent — repos for a given interval are immutable

This means:

- First run: Fetches repo list from GitHub API
- Subsequent runs: Uses cached repos if a superset interval exists

### PR and Commit Caching

All PRs (open, draft, closed, merged) are stored in the database for analytics and historical tracking.

- **Closed/merged PRs**: Read from cache, never refetched (immutable)
- **Open/draft PRs**: Stored but always refetched (may have new commits or state changes)

This means:

- First run: Fetches everything, populates database
- Second run: Uses cache for closed PRs, refetches open/draft PRs and updates their records

## Pre-computed Stats

The cache stores computed values to avoid recalculation:

- `duration_seconds`: PR lifetime in seconds **excluding weekends** (opened to closed/merged)
- `duration_formatted`: Human-readable format (e.g., "3d 5h 12m") - weekends excluded
- `state_pretty`: MERGED/CLOSED/OPEN
- `is_ongoing`: Boolean flag for open PRs
- `jira_ticket`: Extracted Jira ticket number (e.g., VIS-454, CORS-3342)
- `commit_span_seconds`: Time from first commit to last commit **excluding weekends**
- `commit_span_formatted`: Human-readable commit span (e.g., "2d 3h") - weekends excluded

**Note**: All durations automatically exclude weekend time (Saturday and Sunday are not counted)

## Usage

No changes needed — caching is automatic:

```bash
./generate_report.sh miekeuyt 6
```

First run: fetches everything from GitHub API Second run: uses cached data for closed PRs

Output files are written to `../generated/` by default.

## Cache Inspection

View cached repos:

```bash
sqlite3 ../.cache/github_report.db "SELECT username, since_date, COUNT(*) as repo_count FROM repos GROUP BY username, since_date"
sqlite3 ../.cache/github_report.db "SELECT * FROM repos WHERE username='miekeuyt-kasada'"
```

View cached PRs:

```bash
sqlite3 ../.cache/github_report.db "SELECT repo, pr_number, state_pretty, duration_formatted FROM prs"
```

View PRs by Jira ticket:

```bash
sqlite3 ../.cache/github_report.db "SELECT pr_number, title, state_pretty, jira_ticket FROM prs WHERE jira_ticket IS NOT NULL"
sqlite3 ../.cache/github_report.db "SELECT * FROM prs WHERE jira_ticket = 'VIS-454'"
```

Group PRs by Jira ticket:

```bash
sqlite3 ../.cache/github_report.db "SELECT jira_ticket, COUNT(*) as pr_count FROM prs WHERE jira_ticket IS NOT NULL GROUP BY jira_ticket"
```

Clear cache:

```bash
rm ../.cache/github_report.db
```

## Benefits

- **Speed**: 10-50x faster on repeated runs (depending on PR count)
- **API limits**: Reduces GitHub API usage
- **Analytics**: Easy to query across repos/time periods
- **Consistency**: Pre-computed stats ensure identical formatting
