/**
 * Apex Action tool: runs an LLM-supplied SOQL query with a default row limit.
 *
 * Not bulk-mergeable: each input carries an independent, arbitrary query string,
 * so there is no shared key to group on the way ApexAgentGetRecordDetails groups by object
 * type. ApexAgentToolExecutor only ever invokes this action with a single input.
 */
public with sharing class ApexAgentQueryRecords {

    private static final Integer DEFAULT_LIMIT = 50;
    private static final Integer GROUP_BY_LIMIT = 200;

    private static final Pattern LIMIT_PATTERN  = Pattern.compile('(?i)\\bLIMIT\\s+(\\d+)');
    private static final Pattern AGGREGATE_FUNCTION_PATTERN =
        Pattern.compile('(?i)\\b(COUNT|COUNT_DISTINCT|SUM|AVG|MIN|MAX)\\s*\\(');
    private static final Pattern COUNT_ONLY_PATTERN =
        Pattern.compile('(?i)^SELECT\\s+COUNT\\s*\\(\\s*\\)\\s+FROM\\b');
    // Clauses that must follow LIMIT: OFFSET, the FOR/UPDATE row-locking and view-tracking
    // clauses, and ALL ROWS. A default LIMIT has to be inserted before the first of them.
    private static final Pattern TRAILING_CLAUSE_PATTERN =
        Pattern.compile('(?i)\\b(OFFSET|FOR\\s+(VIEW|REFERENCE|UPDATE)|UPDATE\\s+(TRACKING|VIEWSTAT)|ALL\\s+ROWS)\\b');
    private static final Pattern GROUP_BY_PATTERN = Pattern.compile('(?i)\\bGROUP\\s+BY\\b');
    private static final Pattern SECURITY_ENFORCED_PATTERN =
        Pattern.compile('(?i)\\bWITH\\s+SECURITY_ENFORCED\\b');

    public class Input {
        @InvocableVariable(required=true label='SOQL Query' description='The SOQL query to execute. A default LIMIT of 50 is applied if none is specified (200 for GROUP BY queries); aggregate queries without GROUP BY are never limited.')
        public String soqlQuery;
    }

    public class Output {
        @InvocableVariable(label='Query' description='The SOQL query that was actually executed, after sanitizing.')
        public String query;

        @InvocableVariable(label='Record Count' description='Number of records returned; for a SELECT COUNT() query, the count itself.')
        public Integer recordCount;

        @InvocableVariable(label='Records' description='The matching records (or aggregate results).')
        public List<SObject> records;

        @InvocableVariable(label='Error' description='Set instead of records when the query failed to run; explains why.')
        public String error;
    }

    @InvocableMethod(label='Query Records' description='Executes a SOQL query and returns matching records. Automatically caps results at 50 records (lower limits are respected, higher limits are reduced to 50). GROUP BY queries are capped at 200 groups instead. Aggregate queries without GROUP BY (COUNT, SUM, etc.) are supported and never limited. SELECT COUNT() returns the count in recordCount; SELECT COUNT(Id) returns it in the records\n\nCritical usage rules:\n- Always construct a valid SOQL query first based on the user\'s request, then pass it to this tool for execution.\n- If the object name is unfamiliar, use ApexAgentSearchObjects first to confirm it exists and get its exact API name.\n- Always use ApexAgentGetObjectDetails first (if not already called) to discover available fields on the object. Use ApexAgentGetFieldDetails if you need deeper field metadata before building your query. Never guess field names.\n\nWhen not to use:\n- You need fuzzy name search within one object → use ApexAgentSearchRecords.\n- You need a single record by ID → use ApexAgentGetRecordDetails.')
    public static List<Output> run(List<Input> inputs) {
        try {
            List<Output> results = new List<Output>();
            for (Input inp : inputs) {
                results.add(processOne(inp));
            }
            return results;
        } catch (Exception e) {
            ApexAgentToolErrorContext.record(e);
            throw e;
        }
    }

    private static Output processOne(Input inp) {
        String soqlQuery = ApexAgentToolInput.requireNotBlank(inp.soqlQuery, 'soqlQuery');
        String sanitized = sanitize(soqlQuery);

        Output o = new Output();
        o.query = sanitized;
        try {
            if (COUNT_ONLY_PATTERN.matcher(sanitized).find()) {
                // SELECT COUNT() returns no rows from Database.query — the count only
                // comes back from countQuery
                o.recordCount = Database.countQuery(sanitized, System.AccessLevel.USER_MODE);
                o.records     = new List<SObject>();
            } else {
                o.records     = Database.query(sanitized, System.AccessLevel.USER_MODE);
                o.recordCount = o.records.size();
            }
        } catch (QueryException e) {
            o.error = e.getMessage();
        }
        return o;
    }

    // ─── Query sanitization ──────────────────────────────────────────────────────

    @TestVisible
    private static String sanitize(String query) {
        // 1. Trim
        query = query.trim();

        // 2. Strip trailing semicolon
        if (query.endsWith(';')) {
            query = query.removeEnd(';').trim();
        }

        // 3. Remove WITH SECURITY_ENFORCED (USER_MODE handles security)
        query = removeOutsideLiterals(query, SECURITY_ENFORCED_PATTERN).trim();

        // 4. Detect and enforce LIMIT. A plain aggregate (COUNT/SUM/... with no GROUP BY)
        // is left exactly as written — a LIMIT would only get in the way of a single-row
        // result. GROUP BY can return up to 2000 rows, so it gets a higher cap instead.
        String masked = maskStringLiterals(query);
        String topLevel = collapseParentheses(masked);
        if (GROUP_BY_PATTERN.matcher(topLevel).find()) {
            return enforceLimit(query, masked, GROUP_BY_LIMIT);
        }
        if (AGGREGATE_FUNCTION_PATTERN.matcher(topLevel).find()) {
            return query;
        }
        return enforceLimit(query, masked, DEFAULT_LIMIT);
    }

    /**
     * Returns a copy of the query, the same length, with the contents of every quoted
     * string literal blanked out (the quotes themselves stay). Every keyword/clause
     * pattern below runs against this copy, so text inside a literal — e.g.
     * "WHERE Name LIKE '%Offset%'" — is never mistaken for SOQL syntax, and any match
     * position can be applied to the original query unchanged. A backslash escapes the
     * next character (\' and \\), as in SOQL. An unterminated literal is blanked to the
     * end; SOQL will reject that query on its own.
     */
    @TestVisible
    private static String maskStringLiterals(String query) {
        List<String> chars = new List<String>();
        Boolean inLiteral = false;
        Integer length = query.length();
        for (Integer i = 0; i < length; i++) {
            String c = query.substring(i, i + 1);
            if (!inLiteral) {
                inLiteral = (c == '\'');
                chars.add(c);
            } else if (c == '\\') {
                chars.add(' ');
                if (i + 1 < length) {
                    chars.add(' ');
                    i++;
                }
            } else if (c == '\'') {
                inLiteral = false;
                chars.add(c);
            } else {
                chars.add(' ');
            }
        }
        return String.join(chars, '');
    }

    /** Removes every match of the pattern that is outside a string literal. */
    private static String removeOutsideLiterals(String query, Pattern pattern) {
        Matcher m = pattern.matcher(maskStringLiterals(query));
        String result = '';
        Integer copiedUpTo = 0;
        while (m.find()) {
            result += query.substring(copiedUpTo, m.start());
            copiedUpTo = m.end();
        }
        return result + query.substring(copiedUpTo);
    }

    /**
     * The literal-masked query with every parenthesized group collapsed to "()", so the
     * aggregate/GROUP BY checks only see the outer query: a subquery's own COUNT() or
     * GROUP BY does not make a plain outer query look like an aggregate. The function
     * name before the parenthesis (e.g. COUNT) survives the collapse.
     */
    private static String collapseParentheses(String masked) {
        String topLevel = '';
        Integer depth = 0;
        for (Integer i = 0; i < masked.length(); i++) {
            String c = masked.substring(i, i + 1);
            if (c == '(') {
                if (depth == 0) {
                    topLevel += '(';
                }
                depth++;
            } else if (c == ')') {
                depth--;
                if (depth == 0) {
                    topLevel += ')';
                }
            } else if (depth == 0) {
                topLevel += c;
            }
        }
        return topLevel;
    }

    /**
     * Enforces maxLimit on the query's own (outer) LIMIT clause. Only the region
     * after the last top-level closing parenthesis is searched, so a subquery's LIMIT
     * (e.g. "(SELECT Id FROM Contacts LIMIT 200)") is never mistaken for the outer
     * query's LIMIT — LIMIT_PATTERN.find() on the whole string would otherwise match
     * whichever LIMIT appears first, which for a query with a subquery is the
     * subquery's, leaving the outer query unbounded. The search runs on the
     * literal-masked copy; edits are applied to the original query.
     */
    private static String enforceLimit(String query, String masked, Integer maxLimit) {
        Integer searchFrom = masked.lastIndexOf(')') + 1; // 0 when there's no subquery/tuple at all

        Matcher limitMatcher = LIMIT_PATTERN.matcher(masked.substring(searchFrom));
        if (!limitMatcher.find()) {
            return insertLimit(query, masked, searchFrom, maxLimit);
        }

        // Leading zeros don't count, and a number too long for an Integer is certainly
        // above the maximum
        String digits = limitMatcher.group(1).replaceFirst('^0+', '');
        if (digits.length() <= 9 && (digits.length() == 0 || Integer.valueOf(digits) <= maxLimit)) {
            return query;
        }

        return query.substring(0, searchFrom + limitMatcher.start())
            + 'LIMIT ' + maxLimit
            + query.substring(searchFrom + limitMatcher.end());
    }

    /**
     * Adds maxLimit as the LIMIT of a query that has none. It goes before any OFFSET,
     * FOR VIEW/REFERENCE/UPDATE, UPDATE TRACKING/VIEWSTAT or ALL ROWS clause, since
     * SOQL rejects a LIMIT that comes after those; otherwise it is appended.
     */
    private static String insertLimit(String query, String masked, Integer outerStart, Integer maxLimit) {
        Matcher trailing = TRAILING_CLAUSE_PATTERN.matcher(masked.substring(outerStart));
        if (!trailing.find()) {
            return query + ' LIMIT ' + maxLimit;
        }
        Integer insertAt = outerStart + trailing.start();
        return query.substring(0, insertAt).trim() + ' LIMIT ' + maxLimit + ' ' + query.substring(insertAt);
    }
}
