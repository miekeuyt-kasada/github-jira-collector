# JIRA Ticket Pattern Analysis

Analysis of 46 cached JIRA tickets to identify patterns and implied work.

## Ticket Type Distribution

| Type            | Count | %   |
| --------------- | ----- | --- |
| Task            | 23    | 50% |
| UI Task         | 10    | 22% |
| Bug             | 7     | 15% |
| Frontend - Task | 4     | 9%  |
| Sub-task        | 1     | 2%  |
| Epic            | 1     | 2%  |

## Patterns by Ticket Type

### Bug Tickets (15% of total)

**Examples:**

- "Endpoint config - cannot edit endpoints on edit domain name page"
- "Nested buttons warning showing up in test runs warns of hydration problems"
- "path pattern case sensitivity logic relies on equality, not case sensitivity"

**Implied Work:**

- ✅ Testing (to verify bug is fixed)
- ✅ Investigation/debugging
- ❌ NOT implied: Responsive work, new features

**Detection keywords:** `issue_type = "Bug"`

---

### UI Task Tickets (22% of total)

**Summary patterns:**

- "**Create** [component/page]" (6 tickets)
- "Add functionality to..."
- "Add new 404 not found page image..."

**Examples:**

- "Create general layout (using placeholder components) for the Verified Bot settings page"
- "Create main portion of shared header for Verified Bot details pages"
- "Add functionality to collapse and expand filter bar chips"

**Implied Work:**

- ✅ Component implementation
- ❌ NOT implied: Testing (unless explicitly mentioned)
- ❌ NOT implied: Responsive work (unless mentioned)

**Pattern:** "Create" UI tasks are about scaffolding/building, not necessarily about polish or testing.

---

### Task Tickets with "chore(DX)" (multiple instances)

**Examples:**

- "chore(DX): Consolidate search/filter dropdown component usage across endpoint & domainname pages (DRY)"
- "ESLint flat config migration 8 -> 9"
- "Update gitignore to not include buildy things"

**Implied Work:**

- ✅ Code quality improvements
- ✅ Refactoring (explicitly in scope)
- ✅ Type/lint fixes
- ✅ Dependency updates
- ❌ NOT implied: New features

**Detection keywords:** `summary LIKE "%chore(dx)%" OR summary LIKE "%chore(DX)%"`

---

### Task Tickets with "Update..." (9 instances)

**Examples:**

- "Update to use umbrella deps for radix-ui"
- "Update registry badge component & update usages where necessary"
- "Update validation message for conflicting path patterns"
- "Update Methods defaulting and **UI responsive behavior** for Endpoints Flows"

**Implied Work:**

- ✅ Modification of existing code
- ⚠️ **Responsive work IF mentioned** (see last example)
- ❌ NOT implied: Testing (unless it's "Update tests")

**Detection keywords:** `summary LIKE "Update%"`

**Important caveat:** One ticket explicitly mentions "UI responsive behavior" — so responsive IS implied for that
specific ticket.

---

### Task Tickets with "Replace..." / "Remove..." (5 instances)

**Examples:**

- "Replace MUI Snackbar notifications with toasts"
- "Replace useClipboard hook with native navigator.clipboard.writeText API"
- "Remove alias importing (@/...) in favor of absolute imports (src/...)"
- "Remove old sidenav and only use new one"

**Implied Work:**

- ✅ Refactoring (inherent in replacement)
- ✅ Code cleanup
- ✅ Testing (to ensure replacement works)
- ❌ NOT implied: New features beyond the replacement

**Detection keywords:** `summary LIKE "Replace%" OR summary LIKE "Remove%"`

---

### Task Tickets with "Add validation..." (3 instances)

**Examples:**

- "Add validation logic to prevent path patterns with query parameters supplied"
- "Apply form validation to domain name creation input to catch duplicate domain names"
- "Update validation message for conflicting path patterns"

**Implied Work:**

- ✅ Validation logic (obviously)
- ✅ Error handling
- ✅ Testing (to verify validation works)
- ❌ NOT implied: Responsive, styling

**Detection keywords:** `summary LIKE "%validat%"`

---

### Task Tickets with "Unit tests for..." (1 explicit instance)

**Example:**

- "Unit tests for VIS-449, VIS-445, VIS-468"

**Implied Work:**

- ✅ Testing (explicitly in scope)
- ❌ NOT bonus: Any testing done on this ticket

**Detection keywords:** `summary LIKE "%test%" OR summary LIKE "%Test%"`

---

### Migration Tickets (1 instance)

**Example:**

- "ESLint flat config migration 8 -> 9"

**Implied Work:**

- ✅ Refactoring (massive refactoring)
- ✅ Testing (to ensure migration works)
- ✅ Dependency updates
- ✅ Code cleanup
- ✅ Type/lint fixes
- ❌ Nothing is bonus work for migrations — it's all implied

**Detection keywords:** `summary LIKE "%migrat%" OR description LIKE "%migrat%"`

---

## Keyword Patterns in Summaries

### Explicit Work Mentioned

| Keyword                   | Count | Implication                                               |
| ------------------------- | ----- | --------------------------------------------------------- |
| "test" / "Test"           | 3     | Testing is in scope                                       |
| "validation" / "validate" | 3     | Validation logic in scope                                 |
| "responsive"              | 1     | Responsive work in scope (only when explicitly mentioned) |
| "migration"               | 1     | Refactoring + testing + cleanup all in scope              |
| "chore(DX)"               | 1     | Code quality + refactoring in scope                       |

### Action Verbs

| Verb    | Count | Typical Scope                                                      |
| ------- | ----- | ------------------------------------------------------------------ |
| Create  | 6     | Build new component/page (NOT responsive/testing unless mentioned) |
| Update  | 9     | Modify existing (testing NOT implied unless "Update tests")        |
| Add     | 8     | Add new functionality (testing NOT implied)                        |
| Replace | 3     | Refactoring + testing implied                                      |
| Remove  | 2     | Cleanup + refactoring + testing implied                            |

---

## Updated Implied Work Detection Logic

### 1. Testing is IMPLIED if:

```bash
# Bug fixes
issue_type = "Bug"

# Explicit testing tickets
summary LIKE "%test%"

# Validation tickets (need to test validation)
summary LIKE "%validat%"

# Replacements (need to verify replacement works)
summary LIKE "Replace%"

# Removals (need to verify nothing broke)
summary LIKE "Remove%"

# Migrations
summary LIKE "%migrat%"
```

### 2. Refactoring is IMPLIED if:

```bash
# chore(DX) tickets
summary LIKE "%chore(dx)%" OR summary LIKE "%chore(DX)%"

# Explicit refactoring
summary LIKE "%refactor%" OR description LIKE "%refactor%"

# Replacements
summary LIKE "Replace%"

# Removals
summary LIKE "Remove%"

# Cleanup tickets
summary LIKE "%cleanup%"

# Migrations
summary LIKE "%migrat%"

# DRY/consolidation
summary LIKE "%consolidat%" OR summary LIKE "%DRY%"
```

### 3. Type/Lint improvements are IMPLIED if:

```bash
# chore(DX) tickets
summary LIKE "%chore(dx)%" OR summary LIKE "%chore(DX)%"

# ESLint tickets
summary LIKE "%eslint%" OR summary LIKE "%ESLint%"

# TypeScript tickets
summary LIKE "%typescript%" OR summary LIKE "%TypeScript%"

# Migrations (often involve type updates)
summary LIKE "%migrat%"
```

### 4. Responsive work is IMPLIED if:

```bash
# Explicitly mentioned in summary
summary LIKE "%responsive%" OR summary LIKE "%mobile%"

# Explicitly mentioned in description
description LIKE "%responsive%" OR description LIKE "%mobile%"

# Accessibility tickets
summary LIKE "%accessib%" OR summary LIKE "%a11y%"
```

### 5. Validation is IMPLIED if:

```bash
# Explicit validation tickets
summary LIKE "%validat%"

# Form work often implies validation
summary LIKE "%form%" AND (summary LIKE "%creat%" OR summary LIKE "%add%")
```

---

## What's NOT Implied (Bonus Work Opportunities)

### Simple "Create" UI Tasks

- "Create general layout..."
- "Create routes + skeleton pages..."

**NOT IMPLIED:**

- Testing
- Responsive design
- Accessibility improvements
- Type improvements

### Simple "Add" Feature Tasks

- "Add functionality to collapse..."
- "Add new 404 not found page image..."

**NOT IMPLIED:**

- Testing
- Responsive design
- Validation (unless the feature is about validation)

### Simple "Update" Tasks (non-DX)

- "Update documentation link..."
- "Update gitignore..."

**NOT IMPLIED:**

- Testing
- Refactoring (unless it's a Replace/Remove)

---

## Real Examples for Calibration

### Example 1: UI Task with Testing Added

**Ticket:** "Create preview view for Verified Bot settings page"

- Type: UI Task
- Keywords: "Create"
- **Implied:** Component implementation
- **NOT implied:** Testing

**If PR includes:** tests **Result:** ✅ Tests are BONUS WORK

---

### Example 2: Bug Fix with Tests

**Ticket:** "Nested buttons warning showing up in test runs"

- Type: Bug
- **Implied:** Testing (to verify fix works)

**If PR includes:** tests **Result:** ❌ Tests are NOT bonus (implied for bugs)

---

### Example 3: chore(DX) with Refactoring

**Ticket:** "chore(DX): Consolidate search/filter dropdown component usage"

- Type: Task
- Keywords: "chore(DX)", "Consolidate", "DRY"
- **Implied:** Refactoring, code cleanup, possibly testing

**If PR includes:** refactoring + cleanup + tests **Result:** ❌ NOT bonus (all implied for DX chores)

---

### Example 4: Migration with Everything

**Ticket:** "ESLint flat config migration 8 -> 9"

- Type: Task
- Keywords: "migration"
- **Implied:** EVERYTHING (refactoring, testing, type fixes, cleanup, dep updates)

**If PR includes:** all of the above **Result:** ❌ NOT bonus (migrations imply comprehensive work)

---

### Example 5: Replace with Responsive Added

**Ticket:** "Replace MUI Snackbar notifications with toasts"

- Type: Task
- Keywords: "Replace"
- **Implied:** Refactoring, testing

**If PR includes:** tests + refactoring + responsive design **Result:**

- ❌ Tests NOT bonus (implied)
- ❌ Refactoring NOT bonus (implied)
- ✅ Responsive design IS bonus (not mentioned or implied)

---

### Example 6: Responsive Explicitly Mentioned

**Ticket:** "Update Methods defaulting and UI **responsive behavior** for Endpoints Flows"

- Type: Task
- Keywords: "Update", "responsive behavior"
- **Implied:** Responsive work (explicitly mentioned)

**If PR includes:** responsive design **Result:** ❌ Responsive NOT bonus (explicitly in scope)

---

## Summary for Script Implementation

### High-Confidence Implied Work Patterns

```bash
# Testing implied by:
Bug fixes, "test" in summary, "validation" in summary,
Replace/Remove tickets, migrations

# Refactoring implied by:
chore(DX), Replace/Remove, migrations, "refactor" in summary,
"consolidate" in summary, "cleanup" in summary

# Type/lint implied by:
chore(DX), ESLint tickets, TypeScript tickets, migrations

# Responsive implied by:
"responsive" in summary/description, "mobile" in summary/description

# Validation implied by:
"validat" in summary/description
```

### Low-Confidence (Testing NOT implied)

```bash
Simple "Create" UI Tasks (unless explicitly mentioned)
Simple "Add" feature tasks (unless explicitly mentioned)
Simple "Update" tasks (unless explicitly mentioned)
```

These are the best candidates for bonus work when testing/responsive/etc. are added.
