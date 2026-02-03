# Jira Integration

This module provides caching and API integration with Jira Cloud to fetch ticket metadata for enriching brag doc items.

## Setup

### 1. Create Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Give it a name (e.g., "Brag Doc Generator")
4. Copy the token

### 2. Configure Environment Variables

Create or edit `.env.local` in the project root:

```bash
# Required
JIRA_EMAIL=your-email@kasada.io
JIRA_API_TOKEN=your-token-here
JIRA_BASE_URL=https://kasada.atlassian.net

# Optional - will auto-discover if not set, or use default values
JIRA_EPIC_FIELD=customfield_10009              # Epic Link (e.g., "VIS-98")
JIRA_EPIC_NAME_FIELD=customfield_10008         # Epic Name (e.g., "Threat Sessions MVP")
JIRA_SPRINT_FIELD=customfield_10007            # Sprint
JIRA_STORY_POINTS_FIELD=customfield_11004      # Story Points
JIRA_CHAPTER_FIELD=customfield_11782           # Chapter (primary)
JIRA_CHAPTER_ALT_FIELD=customfield_12384       # Chapter (alternative)
JIRA_SERVICE_FIELD=customfield_11783           # Service (primary)
JIRA_SERVICE_ALT_FIELD=customfield_12383       # Service (alternative)
JIRA_CAPEX_OPEX_FIELD=customfield_11280        # CAPEX vs OPEX classification
```

### 3. Load Environment

```bash
source .env.local
export JIRA_EMAIL JIRA_API_TOKEN JIRA_BASE_URL
export JIRA_EPIC_FIELD JIRA_EPIC_NAME_FIELD JIRA_SPRINT_FIELD JIRA_STORY_POINTS_FIELD
export JIRA_CHAPTER_FIELD JIRA_CHAPTER_ALT_FIELD JIRA_SERVICE_FIELD JIRA_SERVICE_ALT_FIELD JIRA_CAPEX_OPEX_FIELD
```

### 4. Initialize History Table

Run the migration to add the history table:

```bash
./github-summary/scripts/database/migrations/migrate_add_jira_history.sh
```

This adds the `jira_ticket_history` table for caching JIRA changelog data.

### 5. Discover Custom Fields (Optional)

Run the discovery script to find your Jira instance's epic field ID:

```bash
./github-summary/scripts/api/discover_jira_fields.sh
```

This will output all custom field IDs for your Jira instance. Look for fields like:
- Epic Link
- Epic Name
- Sprint
- Story Points
- Chapter
- Service
- CAPEX vs OPEX

Add the relevant field IDs to your `.env.local`.

## Architecture

### Database

SQLite database at `.cache/jira_tickets.db` caches ticket metadata and history:

#### Table: `jira_tickets`

- **Closed tickets**: Cached permanently (immutable)
- **Open tickets**: Cached for 24 hours (TTL)

Schema includes:
- Basic fields: `summary`, `description`, `status`, `issue_type`, `priority`
- People: `assignee`, `reporter` (with account IDs)
- Relationships: `epic_key`, `epic_name`, `epic_title`, `parent_key`
- Categorization: `chapter`, `service`, `capex_opex`, `story_points`
- Metadata: `labels` (JSON array), `resolution`, timestamps

#### Table: `jira_ticket_history` (New)

Caches JIRA changelog for tracking ticket changes over time:

- **Closed tickets**: History cached permanently (immutable)
- **Open tickets**: History refetched on each request (status might change)

Schema includes:
- `ticket_key`: Ticket identifier (e.g., VIS-454)
- `field_name`: Field that changed (e.g., status, assignee)
- `old_value`, `new_value`: Before/after values
- `changed_at`: Timestamp of change
- `changed_by`: User who made the change

**Use cases:**
- Track when tickets moved to "Done"
- Detect blocked periods (status = "Waiting", "Blocked")
- Calculate cycle time (Created → In Progress → Done)
- Historical queries ("What was this ticket's status on Dec 1?")

**Smart Field Merging:**
- **Chapter/Service**: Intelligently merges values from both primary and alternative fields
  - Uses whichever field has data
  - Filters out "Template Only" values
  - Concatenates with " / " if both fields have different non-template values
  - Handles both single objects and arrays of objects

### Scripts

1. **`api/discover_jira_fields.sh`** - One-time setup to find custom field IDs
2. **`database/jira_init.sh`** - Initialize the SQLite database
3. **`database/jira_helpers.sh`** - Helper functions for caching and queries
4. **`api/get_jira_ticket.sh`** - Fetch and cache tickets from Jira API

## Usage

### Fetch Single Ticket

```bash
./github-summary/scripts/api/get_jira_ticket.sh VIS-454
```

**Automatic history caching:** If the ticket is closed (Done/Resolved/Closed), the script automatically fetches and caches its changelog. This is a one-time operation — subsequent calls use the cached history.

Output (JSON):
```json
[
  {
    "ticket_key": "VIS-454",
    "summary": "Add validation to endpoint",
    "status": "Done",
    "issue_type": "Task",
    "epic_key": "VIS-400",
    "labels": "[\"frontend\",\"validation\"]",
    ...
  }
]
```

### Fetch Multiple Tickets

```bash
./github-summary/scripts/api/get_jira_ticket.sh VIS-454 VIS-455 VIS-456
```

### Using Helper Functions

Source the helpers in your scripts:

```bash
source ./github-summary/scripts/database/jira_helpers.sh

# Check if ticket metadata is cached
if is_jira_cached "VIS-454"; then
  echo "Ticket is cached and closed"
fi

# Get cached ticket metadata
ticket_data=$(get_cached_jira_ticket "VIS-454")

# Get all tickets for an epic
epic_tickets=$(get_tickets_by_epic "VIS-400")

# Get all epic keys
all_epics=$(get_all_epic_keys)

# Check if ticket history is cached
if is_jira_history_cached "VIS-454"; then
  echo "History is cached"
fi

# Get status transitions for a ticket
status_history=$(get_jira_status_history "VIS-454")

# Get blocked periods (status contained block/wait/hold/park)
blocked_periods=$(get_jira_blocked_periods "VIS-454")

# Get full changelog for a ticket
full_history=$(get_jira_full_history "VIS-454")
```

## Testing

Run the unit tests:

```bash
# Test Jira helpers
bats tests/unit/jira_helpers.bats

# Test clustering logic (if needed later)
bats tests/unit/cluster_brag_items.bats
```

## API Details

### Authentication

Uses HTTP Basic Auth with base64-encoded `email:token`:

```bash
Authorization: Basic $(echo -n "$JIRA_EMAIL:$JIRA_API_TOKEN" | base64)
```

### Endpoint

```
GET $JIRA_BASE_URL/rest/api/3/issue/{ticketKey}?fields=...
```

### Fields Fetched

**Standard Fields:**
- `summary` - Issue title
- `description` - Issue body (Atlassian Document Format, converted to plain text)
- `status` - Current status
- `issuetype` - Issue type (Story, Task, Bug, Epic, etc.)
- `assignee` - Assigned user (with account ID)
- `reporter` - Creator (with account ID)
- `priority` - Priority level
- `parent` - Parent issue (for subtasks)
- `labels` - Array of labels
- `resolution` - Resolution status
- `created`, `updated`, `resolutiondate` - Timestamps

**Custom Fields (configurable via environment variables):**
- `$JIRA_EPIC_FIELD` - Epic Link (default: `customfield_10009`) - VIS-98
- `$JIRA_EPIC_NAME_FIELD` - Epic Name (default: `customfield_10008`) - "Threat Sessions MVP" 
- `$JIRA_SPRINT_FIELD` - Sprint (default: `customfield_10007`)
- `$JIRA_STORY_POINTS_FIELD` - Story Points (default: `customfield_11004`)
- `$JIRA_CHAPTER_FIELD` - Chapter primary (default: `customfield_11782`)
- `$JIRA_CHAPTER_ALT_FIELD` - Chapter alternative (default: `customfield_12384`)
- `$JIRA_SERVICE_FIELD` - Service primary (default: `customfield_11783`)
- `$JIRA_SERVICE_ALT_FIELD` - Service alternative (default: `customfield_12383`)
- `$JIRA_CAPEX_OPEX_FIELD` - CAPEX vs OPEX (default: `customfield_11280`)

## Troubleshooting

### "Required environment variables not set"

Make sure you've sourced `.env.local` and exported the variables:

```bash
source .env.local && export JIRA_EMAIL JIRA_API_TOKEN JIRA_BASE_URL
```

### "Error fetching fields from Jira"

Check your API token and email are correct. Try accessing Jira manually:

```bash
curl -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_BASE_URL/rest/api/3/myself"
```

### Epic field not found

Run the discovery script to find the correct field ID for your instance:

```bash
./github-summary/scripts/api/discover_jira_fields.sh
```

## Helper Scripts

### Get Blocked Time

Calculate how many days a ticket was in blocked status during a date range:

```bash
./github-summary/scripts/analysis/get_jira_blocked_time.sh VIS-454 2025-10-01 2025-11-01
```

Output: Number of days (e.g., `15`)

**Uses cached history when available** — if the ticket is closed and history is cached, no API calls are made.

**Used by:** `analyze_pr_effort.sh` automatically uses this to subtract blocked time from PR effort calculations.

## Future Integration

The enrichment and clustering scripts are available but not yet integrated into the main pipeline:

- `compose/enrich_with_jira.sh` - Enrich brag docs with Jira metadata
- `steps/cluster_brag_items.sh` - Cluster related items by epic/ticket

These will be integrated after the Jira integration is tested and working.
