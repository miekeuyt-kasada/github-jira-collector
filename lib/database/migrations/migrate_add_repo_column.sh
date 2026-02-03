#!/bin/bash
# Add repo column to brag_items table
# Usage: source .env.local && export DATABASE_URL && ./migrate_add_repo_column.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════"
echo "Adding repo column to brag_items"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check for psql
if ! command -v psql &> /dev/null; then
  echo -e "${RED}❌ Error: psql is not installed${NC}"
  exit 1
fi

# Check for connection string
POSTGRES_URL="${DATABASE_URL:-$POSTGRES_URL}"

if [ -z "$POSTGRES_URL" ]; then
  echo -e "${RED}❌ Error: DATABASE_URL environment variable not set${NC}"
  echo "Set it with: source .env.local && export DATABASE_URL"
  exit 1
fi

# Test connection
echo "🔌 Testing database connection..."
if ! psql "$POSTGRES_URL" -c "SELECT 1;" &> /dev/null; then
  echo -e "${RED}❌ Error: Cannot connect to Postgres database${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Connection successful${NC}"
echo ""

# Add repo column
echo "📋 Adding repo column..."
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 <<'EOF'
-- Add repo column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'brag_items' AND column_name = 'repo'
  ) THEN
    ALTER TABLE brag_items ADD COLUMN repo TEXT;
    RAISE NOTICE 'Added repo column';
  ELSE
    RAISE NOTICE 'repo column already exists';
  END IF;
END $$;

-- Create index for repo queries
CREATE INDEX IF NOT EXISTS idx_brag_items_repo ON brag_items(repo);
EOF

echo ""
echo -e "${GREEN}✅ Migration complete!${NC}"
echo ""

# Show updated schema
echo "📊 Updated schema:"
psql "$POSTGRES_URL" -c "\d brag_items" 2>/dev/null | head -25

echo ""
echo "════════════════════════════════════════════════════════════════"


