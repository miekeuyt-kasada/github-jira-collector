#!/bin/bash
# Initialize SQLite database for GitHub report caching
# Usage: ./db_init.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache"
DB_PATH="$CACHE_DIR/github_data.db"

mkdir -p "$CACHE_DIR"

sqlite3 "$DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS prs (
  repo TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  title TEXT,
  state TEXT,
  draft INTEGER,
  created_at TEXT,
  closed_at TEXT,
  merged_at TEXT,
  description TEXT,
  fetched_at TEXT,
  duration_seconds INTEGER,
  duration_formatted TEXT,
  state_pretty TEXT,
  is_ongoing INTEGER,
  jira_ticket TEXT,
  first_commit_date TEXT,
  last_commit_date TEXT,
  commit_span_seconds INTEGER,
  commit_span_formatted TEXT,
  first_author_date TEXT,
  last_author_date TEXT,
  author_span_seconds INTEGER,
  author_span_formatted TEXT,
  PRIMARY KEY (repo, pr_number)
);

CREATE TABLE IF NOT EXISTS pr_commits (
  repo TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  sha TEXT NOT NULL,
  author TEXT,
  date TEXT,
  author_date TEXT,
  message TEXT,
  fetched_at TEXT,
  PRIMARY KEY (repo, pr_number, sha)
);

CREATE TABLE IF NOT EXISTS direct_commits (
  repo TEXT NOT NULL,
  sha TEXT NOT NULL,
  author TEXT,
  date TEXT,
  message TEXT,
  fetched_at TEXT,
  PRIMARY KEY (repo, sha)
);

CREATE TABLE IF NOT EXISTS repos (
  username TEXT NOT NULL,
  since_date TEXT NOT NULL,
  repo_name TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  PRIMARY KEY (username, since_date, repo_name)
);

CREATE INDEX IF NOT EXISTS idx_prs_state ON prs(repo, state, is_ongoing);
CREATE INDEX IF NOT EXISTS idx_prs_jira ON prs(jira_ticket);
CREATE INDEX IF NOT EXISTS idx_pr_commits_pr ON pr_commits(repo, pr_number);
CREATE INDEX IF NOT EXISTS idx_repos_lookup ON repos(username, since_date);
EOF

echo "✅ Database initialized: $DB_PATH"

