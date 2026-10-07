# SOQL Guidelines

SOQL is SELECT-only. No INSERT/UPDATE/DELETE, no JOIN, no SELECT *, no UNION, no BETWEEN. LLMs hallucinate SQL patterns — follow these rules exactly.

---

## SOQL vs SQL

| SQL | SOQL equivalent |
|---|---|
| `SELECT *` | ❌ — list fields explicitly |
| `JOIN` | ❌ — use relationship traversal (dot notation / subquery) |
| `BETWEEN x AND y` | `>= x AND <= y` |
| `= null` | `IS NULL` |
| Subquery anywhere in WHERE | Only `IN`/`NOT IN` semi-join/anti-join |

Strings in WHERE are **case-insensitive**. Field/object names are case-insensitive but use exact API names.

---

## Syntax Order

```
SELECT fields FROM Object [WHERE] [WITH] [GROUP BY] [HAVING] [ORDER BY] [LIMIT] [OFFSET] [FOR ...]
```

---

## API Names

- Custom objects: `Agent__c`, `LLM__c` — always `__c` suffix
- Custom fields: `Status__c`, `Max_Tokens__c` — always `__c` suffix  
- Standard fields never have `__c`: `Id`, `Name`, `CreatedDate`, `LastModifiedDate`, `OwnerId`

---

## WHERE Operators

```sql
WHERE Name = 'Acme'
WHERE Amount != 0
WHERE Revenue > 1000000
WHERE Name LIKE 'Acme%'          -- % = any chars, _ = one char, case-insensitive
WHERE Industry IN ('Tech', 'Finance')
WHERE Status__c NOT IN ('Closed', 'Cancelled')
WHERE Field__c IS NULL           -- also valid: WHERE Field__c = null
WHERE Field__c IS NOT NULL       -- also valid: WHERE Field__c != null
WHERE (Industry = 'Tech' OR Industry = 'Finance') AND Revenue > 500000
WHERE NOT (Status = 'Closed')

-- Multi-select picklist — never use = or IN
WHERE Tags__c INCLUDES ('Reading', 'Coding')   -- has at least one
WHERE Tags__c EXCLUDES ('Spam')                -- has none of these
WHERE Tags__c INCLUDES ('Reading;Coding')      -- semicolon = AND (must have both)
```

Escape single quotes: `WHERE Name = 'O\'Brien'`  
Nulls in `IN` lists are silently ignored. Nulls in `NOT IN` subqueries are dangerous — see pitfalls.

---

## Date & DateTime

Date literals (no quotes):
```sql
TODAY  YESTERDAY  TOMORROW  THIS_WEEK  LAST_WEEK  THIS_MONTH  LAST_MONTH
THIS_QUARTER  THIS_YEAR  LAST_YEAR  LAST_N_DAYS:30  NEXT_N_DAYS:7
LAST_N_MONTHS:3  LAST_N_WEEKS:2  THIS_FISCAL_YEAR  LAST_FISCAL_QUARTER
LAST_N_FISCAL_YEARS:2
```

Explicit values (no quotes):
```sql
WHERE CloseDate > 2025-01-01                     -- Date: YYYY-MM-DD
WHERE CreatedDate > 2025-01-01T00:00:00Z         -- DateTime: ISO 8601 UTC
WHERE CloseDate >= 2024-06-01 AND CloseDate <= 2024-06-30
```

`LAST_N_DAYS:n` includes today. `'TODAY'` (with quotes) is a string, not a date literal.

Date functions for SELECT/GROUP BY: `CALENDAR_YEAR()`, `CALENDAR_MONTH()`, `CALENDAR_QUARTER()`, `FISCAL_YEAR()`, `FISCAL_QUARTER()`, `DAY_ONLY()` (DateTime→Date), `DAY_IN_MONTH()`, `DAY_IN_WEEK()`, `HOUR_IN_DAY()`, `WEEK_IN_YEAR()`

```sql
SELECT CALENDAR_YEAR(CreatedDate), COUNT(Id) FROM Opportunity GROUP BY CALENDAR_YEAR(CreatedDate)
```

---

## ORDER BY / LIMIT / OFFSET

```sql
ORDER BY AnnualRevenue DESC
ORDER BY LastName ASC, FirstName ASC
ORDER BY CloseDate ASC NULLS LAST    -- default: NULLS LAST for ASC, NULLS FIRST for DESC
ORDER BY Account.Name ASC            -- relationship field

LIMIT 10
LIMIT 10 OFFSET 20    -- OFFSET max = 2,000; use keyset pagination beyond that
```

---

## Aggregate Functions

```sql
COUNT()              -- all rows including nulls
COUNT(field)         -- non-null values only
COUNT_DISTINCT(field)
SUM(field)  AVG(field)  MIN(field)  MAX(field)

-- Always alias aggregate expressions (default names are expr0, expr1...)
SELECT StageName, COUNT(Id) cnt, SUM(Amount) total FROM Opportunity GROUP BY StageName
HAVING COUNT(Id) > 5

-- WHERE filters before grouping; HAVING filters after grouping
SELECT Industry, AVG(AnnualRevenue) avg FROM Account
WHERE AnnualRevenue != null GROUP BY Industry HAVING AVG(AnnualRevenue) > 1000000
```

GROUP BY ROLLUP (subtotals), GROUP BY CUBE (cross-tabular subtotals) — max 3 fields each:
```sql
SELECT Type, BillingCountry, COUNT(Id) FROM Account GROUP BY ROLLUP(Type, BillingCountry)
SELECT Type, BillingCountry, COUNT(Id) FROM Account GROUP BY CUBE(Type, BillingCountry)
-- Use GROUPING(field) to identify subtotal rows: returns 1 for subtotal, 0 for regular
```

---

## Relationship Queries

No JOIN. Use relationship names from the object metadata.

### Child-to-parent (dot notation) — up to 5 levels deep
```sql
SELECT Id, Account.Name, Account.Industry FROM Contact              -- standard
SELECT Id, LLM__r.Name, LLM__r.Family__c FROM Agent__c             -- custom: __c → __r
SELECT Id, Thread_Log__r.Name FROM Message_Log__c                   -- lookup traversal
SELECT Id, Account.Owner.Profile.Name FROM Contact                  -- multi-level
```

**Rule:** `FieldName__c` stores the FK Id. `FieldName__r` traverses into the related object.

### Parent-to-child (subquery in SELECT)
```sql
SELECT Id, Name, (SELECT Id, FirstName FROM Contacts) FROM Account              -- standard
SELECT Id, (SELECT Id, Topic__r.Name FROM Topic_Maps__r) FROM Agent__c          -- custom
SELECT Id, (SELECT Id, Name, Amount FROM Opportunities) FROM Account
```

**Rule:** Child relationship name is the plural form with `__r` for custom (e.g., `Tool_Parameters__r`). Check Setup → Object Manager → child object → Fields & Relationships → relationship field → "Child Relationship Name".

Standard child names: `Contacts`, `Opportunities`, `Cases`, `Tasks`, `OpenActivities`, `ActivityHistories`
Note: `Activities` is not directly queryable — use `OpenActivities` (open tasks/events) or `ActivityHistories` (closed).

### Limits
- Max **55** child-to-parent relationships (dot notation) per query
- Max **1 level** of subquery nesting — no subquery inside a subquery
- Behaves like LEFT OUTER JOIN — parent returned even if no children exist

---

## Subquery Filters (Semi-join / Anti-join)

Only allowed in `IN` / `NOT IN`. Returns one field only. No ORDER BY/LIMIT/OFFSET inside.

```sql
-- Semi-join
SELECT Id FROM Account WHERE Id IN (SELECT AccountId FROM Contact)
SELECT Id FROM Agent__c WHERE LLM__c IN (SELECT Id FROM LLM__c WHERE Family__c = 'Anthropic')

-- Anti-join — MUST filter nulls in subquery
SELECT Id FROM Account WHERE Id NOT IN (SELECT AccountId FROM Contact WHERE AccountId != null)
-- If ANY subquery row has null AccountId, NOT IN returns 0 rows
```

---

## Other Clauses

**FOR UPDATE** — locks rows, no ORDER BY allowed:
```sql
SELECT Id, Name FROM Account WHERE Name = 'Acme' FOR UPDATE
```

**FOR VIEW / FOR REFERENCE** — tracks LastViewedDate / LastReferencedDate

**WITH USER_MODE** — enforces FLS and sharing of running user  
**WITH SYSTEM_MODE** — bypasses FLS and sharing  
**WITH SECURITY_ENFORCED** — throws if user lacks FLS access (older approach)

**ALL ROWS** — includes deleted (Recycle Bin) records and archived Task/Event records:
```sql
SELECT Id FROM Account WHERE IsDeleted = true ALL ROWS
```

**toLabel()** — returns picklist display label instead of API value:
```sql
SELECT Id, toLabel(StageName) FROM Opportunity
```

---

## Common Pitfalls

| Pitfall | Wrong | Right |
|---|---|---|
| Custom field without `__c` | `SELECT Status FROM Agent__c` | `SELECT Status__c FROM Agent__c` |
| FK field instead of `__r` | `SELECT LLM__c FROM Agent__c` | `SELECT LLM__r.Name FROM Agent__c` |
| `AccountId` dot traverse | `SELECT AccountId.Name FROM Contact` | `SELECT Account.Name FROM Contact` |
| Singular child relationship | `(SELECT Id FROM Contact)` | `(SELECT Id FROM Contacts)` |
| Quoted date literal | `WHERE CloseDate = 'TODAY'` | `WHERE CloseDate = TODAY` |
| Null check style | `WHERE Field = null` / `!= null` both work — unlike SQL, SOQL accepts these | Prefer `IS NULL` / `IS NOT NULL` for clarity |
| `=` on multi-select picklist | `WHERE Tags__c = 'A'` | `WHERE Tags__c INCLUDES ('A')` |
| NOT IN without null filter | `NOT IN (SELECT AccountId FROM Contact)` | `NOT IN (SELECT AccountId FROM Contact WHERE AccountId != null)` |
| Missing GROUP BY field | `SELECT Stage, Industry, COUNT(Id) GROUP BY Stage` | `GROUP BY Stage, Industry` |
| OFFSET > 2000 | `OFFSET 3000` | Keyset: `WHERE Name > 'lastValue' LIMIT 200` |

---

## Custom Object Quick Reference

```sql
-- Basic custom object query
SELECT Id, Name, Status__c, Max_Tokens__c FROM Agent__c WHERE Status__c = 'Active'

-- Child-to-parent traversal
SELECT Id, LLM__r.Name, LLM__r.Family__c, LLM__r.Api_Name__c FROM Agent__c

-- Multi-level traversal
SELECT Id, LLM__r.Named_Credential__r.DeveloperName FROM Agent__c

-- Parent-to-child subquery
SELECT Id, Name, (SELECT Id, Topic__r.Name, Order__c FROM Topic_Maps__r WHERE Active__c = true)
FROM Agent__c

-- Junction object query
SELECT Id, Topic__r.Name, Tool__r.Name, Tool__r.Execution_Type__c
FROM Topic_Tool_Map__c WHERE Active__c = true

-- Aggregate
SELECT Status__c, COUNT(Id) cnt, SUM(Input_Tokens__c) totalIn
FROM Message_Log__c WHERE CreatedDate = THIS_MONTH GROUP BY Status__c HAVING COUNT(Id) > 10

-- Semi-join
SELECT Id, Name FROM Agent__c WHERE Id IN (SELECT Agent__c FROM Thread_Log__c WHERE CreatedDate = TODAY)
```