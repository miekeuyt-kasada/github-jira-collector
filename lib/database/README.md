# Brag Doc Database

Postgres database for persisting brag doc items. Uses a Postgres-first architecture — items are written directly to
Postgres during the pipeline.

## Prerequisites

- `psql` — Postgres client (`brew install postgresql` on macOS)
- `DATABASE_URL` environment variable

## Setup

### With Vercel + Neon (recommended)

Neon has native Vercel integration that auto-configures your database.

1. **Add Neon to your Vercel project**

   - Vercel dashboard → your project → Storage tab
   - Click "Create Database" → Select "Neon"
   - Free tier: 0.5 GB storage, autoscales to zero

2. **Pull environment variables locally**

   ```bash
   vercel env pull
   ```

3. **Source and export**
   ```bash
   source .env.local && export DATABASE_URL
   ```

### With other Postgres providers

```bash
export DATABASE_URL='postgres://user:pass@host:port/database'
```

## Schema

```sql
brag_items (
  id SERIAL PRIMARY KEY,
  achievement TEXT,
  dates JSONB,           -- Array of date strings
  company_goals JSONB,   -- Array of {tag, description}
  growth_areas JSONB,    -- Array of {tag, description}
  outcomes TEXT,
  impact TEXT,
  pr_id INTEGER,
  ticket_no TEXT,
  commit_shas JSONB,     -- Array of commit SHAs
  event_id TEXT,         -- For manual events (non-PR)
  repo TEXT,
  state TEXT,
  month TEXT,            -- YYYY-MM
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
```

## Deduplication

Items are deduplicated in order of priority:

1. **`pr_id`** — Most items have this (PR-based work)
2. **`event_id`** — For manual events (awards, presentations)
3. **`commit_shas`** — Fallback for items without PR or event ID

This ensures no duplicates per identifier per month, even when LLM-generated content varies between runs.

## Querying

### From psql

```bash
# Test connection
psql "$DATABASE_URL" -c "SELECT 1;"

# Get items by month
psql "$DATABASE_URL" -c "
  SELECT month, COUNT(*) as items
  FROM brag_items
  GROUP BY month
  ORDER BY month;
"

# Search by company goal
psql "$DATABASE_URL" -c "
  SELECT achievement FROM brag_items
  WHERE company_goals @> '[{\"tag\": \"positive-impact\"}]';
"
```

### From your app (TypeScript)

```typescript
import { sql } from '@vercel/postgres';

// Get all items for a month
const { rows } = await sql`
  SELECT * FROM brag_items 
  WHERE month = '2025-11' 
  ORDER BY id
`;

// Search by company goal tag (JSONB query)
const { rows } = await sql`
  SELECT * FROM brag_items 
  WHERE company_goals @> '[{"tag": "positive-impact"}]'
`;

// Get unique growth areas
const { rows } = await sql`
  SELECT DISTINCT jsonb_array_elements(growth_areas)->>'tag' as tag 
  FROM brag_items 
  WHERE growth_areas IS NOT NULL
`;
```

## Helper Scripts

### `postgres_helpers.sh`

Source this to use Postgres utility functions:

```bash
source ./github-summary/scripts/database/postgres_helpers.sh

# Test connection
pg_test_connection

# Get item count for a month
pg_get_month_item_count "2025-11"

# Insert/upsert a brag item
pg_insert_brag_item "$json_item" "2025-11"
```

### Migrations

Migration scripts in `migrations/` handle schema changes:

- `migrate_to_postgres_first.sh` — Initial Postgres setup
- `migrate_add_repo_column.sh` — Add repo field
- `migrate_add_state_column.sh` — Add state field
- And others for backfilling data

## Troubleshooting

**"psql is not installed"**

- macOS: `brew install postgresql`
- Linux: `apt-get install postgresql-client`

**"Cannot connect to Postgres database"**

- Check your connection string format
- For Neon: ensure connection pooling is enabled (default)
- Test: `psql "$DATABASE_URL" -c "SELECT 1;"`

**"DATABASE_URL environment variable not set"**

- Vercel + Neon: run `vercel env pull`
- Otherwise: `export DATABASE_URL='postgres://...'`
- Check `.env.local` exists and has DATABASE_URL
