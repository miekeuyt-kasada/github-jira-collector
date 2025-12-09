# Brag Doc Items Database

SQLite database for persisting interpreted brag doc items.

## Database Location

`github-summary/scripts/.cache/bragdoc_items.db`

## Schema

```sql
brag_items (
  id INTEGER PRIMARY KEY,
  achievement TEXT,
  dates TEXT,          -- JSON array of date strings
  company_goals TEXT,  -- JSON array of {tag, description} objects
  growth_areas TEXT,   -- JSON array of {tag, description} objects
  outcomes TEXT,
  impact TEXT,
  pr_id INTEGER,       -- Unique per month when present
  ticket_no TEXT,      -- Not unique (multiple PRs can share same ticket)
  month TEXT,          -- YYYY-MM
  created_at TEXT,
  updated_at TEXT
)
```

## Usage

### Initialize Database

```bash
./github-summary/scripts/database/bragdoc_db_init.sh
```

### Import Historical Data

```bash
./github-summary/scripts/database/migrations/migrate_import_historical_bragdocs.sh
```

Imports all `month-*-interpreted.json` files from `.temp/` directory.

### Query Helper Functions

Source the helpers to use utility functions:

```bash
source ./github-summary/scripts/database/bragdoc_db_helpers.sh

# Get items for a specific month
get_items_for_month "2025-07"

# Get item by PR ID
get_item_by_pr 1625

# Get item by ticket number
get_item_by_ticket "CORS-4638"

# Export month to JSON file
export_month_to_json "2025-07" "output.json"

# Get statistics
get_item_count
get_month_item_count "2025-07"
get_all_months
```

### Direct SQL Queries

```bash
sqlite3 ./github-summary/scripts/.cache/bragdoc_items.db "
  SELECT month, COUNT(*) as item_count
  FROM brag_items
  GROUP BY month
  ORDER BY month;
"
```

## Automatic Integration

The main workflow (`generate_monthly_bragdocs.sh`) automatically persists items to the database after Phase 4
enrichment.

## Deduplication

Items are automatically deduplicated by `pr_id` per month:

- If `pr_id` matches for the same month, the item is updated (not duplicated)
- Multiple items can share the same `ticket_no` (multiple PRs can work on the same JIRA ticket)
- Items without `pr_id` are inserted as new rows (no deduplication)

This ensures no duplicates per PR per month, even when LLM-generated content varies between runs, while allowing multiple PRs with the same ticket to exist as separate items.

## Syncing to Postgres (Neon/Supabase/etc.)

You can sync your local SQLite database to a serverless Postgres database for remote access and querying from your
Vercel site.

### Setup with Neon (Recommended)

Neon has native Vercel integration that auto-configures your database connection.

1. **Add Neon to your Vercel project**

   - Go to Vercel dashboard → your project → Storage tab
   - Click "Create Database"
   - Select "Neon" (Serverless Postgres)
   - Free tier: 0.5 GB storage, autoscales to zero
   - Database and `DATABASE_URL` env var will be auto-configured

2. **Pull environment variables locally**

   ```bash
   vercel env pull
   ```

   This creates a `.env.local` file with your `DATABASE_URL`.

3. **Run sync script**

   ```bash
   # Source and export the variable, then run sync
   source .env.local && export DATABASE_URL && ./github-summary/scripts/database/sync_to_postgres.sh
   ```

   Or in two steps:

   ```bash
   source .env.local
   export DATABASE_URL
   ./github-summary/scripts/database/sync_to_postgres.sh
   ```

### Setup with Other Postgres Providers

If using Supabase, Turso, or another provider:

```bash
export DATABASE_URL='postgres://username:password@host:port/database'
./github-summary/scripts/database/sync_to_postgres.sh
```

### What it does

- Creates the `brag_items` table with matching schema (if not exists)
- Uses JSONB for JSON fields (better for querying than TEXT)
- Adds indexes for performance (month, pr_id, ticket_no)
- Upserts all items from local database
- Deduplicates on (pr_id, month) only - allows multiple items with same ticket_no
- Reports summary: new inserts, updates, failures

### Sync behavior

- **One-way sync**: Local SQLite → Postgres
- **Manual trigger**: Run the script when you want to push updates
- **Idempotent**: Safe to run multiple times (uses upsert)
- **Atomic**: Each item synced individually with error handling

### Querying from Vercel

Once synced, you can query from your Vercel site using `@vercel/postgres` or your Postgres client:

```typescript
import { Pool } from '@vercel/postgres';

// Get all items for a month
const { rows } = await sql`
  SELECT * FROM brag_items 
  WHERE month = '2025-11' 
  ORDER BY id
`;

// Search by company goal tag (JSONB query)
const { rows } = await sql`
  SELECT * FROM brag_items 
  WHERE company_goals @> '[{"tag": "customer-focus"}]'
`;

// Get all unique company goal tags
const { rows } = await sql`
  SELECT DISTINCT jsonb_array_elements(company_goals)->>'tag' as tag 
  FROM brag_items 
  WHERE company_goals IS NOT NULL
`;

// Get all unique growth area tags
const { rows } = await sql`
  SELECT DISTINCT jsonb_array_elements(growth_areas)->>'tag' as tag 
  FROM brag_items 
  WHERE growth_areas IS NOT NULL
`;
```

### Troubleshooting

**"psql is not installed"**

- macOS: `brew install postgresql`
- Linux: `apt-get install postgresql-client`

**"Cannot connect to Postgres database"**

- Verify your connection string is correct
- For Neon: check connection pooling is enabled (default)
- Test connection: `psql "$DATABASE_URL" -c "SELECT 1;"`

**"DATABASE_URL environment variable not set"**

- If using Vercel + Neon: run `vercel env pull` to get env vars
- Otherwise: `export DATABASE_URL='postgres://...'`
- Check your `.env.local` file exists and has DATABASE_URL
