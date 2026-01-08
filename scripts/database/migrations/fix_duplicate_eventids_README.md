# Manual Event EventId Fix

## Problem Summary

The old eventId generation used base64 encoding (first 8 chars), causing **collisions**:

```
All events got: m-eyJhY2hp
```

### Impact

**JSON Files:**
- ✅ 3 events exist but have duplicate IDs
- November: "Won Android SDK bug bash" 
- December: "Built AI SDK POC"
- December: "Built Tab Overlay Compare"

**Postgres Database:**
- ❌ Only 2 events exist (Nov + one Dec)
- ❌ AI SDK POC event is **missing** (rejected by unique constraint)
- ❌ Both existing events have the same `commit_shas_hash`

## The Fix

### Step 1: Fix JSON Files

```bash
# From project root:
./github-summary/scripts/database/migrations/fix_duplicate_eventids.sh
```

This will:
- Create backups (`.backup` files)
- Assign unique IDs:
  - `m-eyJhY2hp` → `m-8aa64acc` (Android SDK bug bash)
  - `m-eyJhY2hp` → `m-1099c692` (AI SDK POC)  
  - `m-eyJhY2hp` → `m-ff4fb335` (Tab Overlay)

### Step 2: Fix Database

```bash
# From project root:
source .env.local && export DATABASE_URL
./github-summary/scripts/database/migrations/fix_duplicate_eventids_db.sh
```

This will:
- Delete the 2 existing manual events (wrong hashes)
- Re-persist all 3 events from fixed JSON files
- Each will get a unique `commit_shas_hash` (computed from new eventId)
- Verify all 3 are in database

## Why This Happened

1. Old code: `eventId: ("m-" + (. | @json | @base64 | .[0:8]))`
2. All JSON starts with `{"achievement":` → same base64 prefix
3. Database uses `commit_shas_hash` (derived from eventId) for deduplication
4. Unique constraint on `(commit_shas_hash, month)` prevented 3rd insert

## Fix Applied

New code: `item_hash=$(echo "$item" | jq -S -c '.' | shasum -a 256 | cut -d' ' -f1 | head -c 8)`

This uses SHA-256 hash of the entire JSON object → guaranteed unique IDs.

## Verification

After running both scripts from project root:

```bash
# Check JSON files
grep "eventId" bragdoc-data/bragdoc-data-2025-{11,12}.json

# Check database  
source .env.local && export DATABASE_URL
psql "$DATABASE_URL" -c "
  SELECT month, LEFT(achievement, 50), LEFT(commit_shas_hash, 12)
  FROM brag_items 
  WHERE month IN ('2025-11', '2025-12') AND pr_id IS NULL
"
```

Should show 3 unique hashes.
