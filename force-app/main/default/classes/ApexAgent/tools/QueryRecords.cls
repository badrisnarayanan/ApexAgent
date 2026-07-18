public with sharing class QueryRecords implements ApexAgentTool {

    private static final Integer DEFAULT_LIMIT = 50;

    private static final Pattern LIMIT_PATTERN  = Pattern.compile('(?i)\\bLIMIT\\s+(\\d+)');
    private static final Pattern SECURITY_ENFORCED_PATTERN =
        Pattern.compile('(?i)\\bWITH\\s+SECURITY_ENFORCED\\b');

    public Object execute(Map<String, Object> input) {
        ApexAgentToolInput.requireMap(input);
        String soqlQuery = ApexAgentToolInput.requireString(input, 'soqlQuery');

        String sanitized = sanitize(soqlQuery);

        try {
            List<SObject> records = Database.query(sanitized, System.AccessLevel.USER_MODE);
            return new Map<String, Object>{
                'query'       => sanitized,
                'recordCount' => records.size(),
                'records'     => records
            };
        } catch (QueryException e) {
            return new Map<String, Object>{
                'query'     => sanitized,
                'exception' => e.getMessage()
            };
        }
    }

    // ─── Query sanitization ──────────────────────────────────────────────────────

    @TestVisible
    private String sanitize(String query) {
        // 1. Trim
        query = query.trim();

        // 2. Strip trailing semicolon
        if (query.endsWith(';')) {
            query = query.removeEnd(';').trim();
        }

        // 3. Remove WITH SECURITY_ENFORCED (USER_MODE handles security)
        query = SECURITY_ENFORCED_PATTERN.matcher(query).replaceAll('').trim();

        // 4. Detect and enforce LIMIT — applied to aggregate queries too (SOQL
        // aggregates accept LIMIT; a plain aggregate with no GROUP BY still
        // collapses to one row regardless, so this is always safe to add).
        return enforceLimit(query);
    }

    /**
     * Enforces DEFAULT_LIMIT on the query's own (outer) LIMIT clause. Only the region
     * after the last top-level closing parenthesis is searched, so a subquery's LIMIT
     * (e.g. "(SELECT Id FROM Contacts LIMIT 200)") is never mistaken for the outer
     * query's LIMIT — LIMIT_PATTERN.find() on the whole string would otherwise match
     * whichever LIMIT appears first, which for a query with a subquery is the
     * subquery's, leaving the outer query unbounded.
     */
    private String enforceLimit(String query) {
        Integer searchFrom = query.lastIndexOf(')') + 1; // 0 when there's no subquery/tuple at all
        String outerRegion = query.substring(searchFrom);

        Matcher limitMatcher = LIMIT_PATTERN.matcher(outerRegion);
        if (!limitMatcher.find()) {
            return query + ' LIMIT ' + DEFAULT_LIMIT;
        }

        Integer existingLimit = Integer.valueOf(limitMatcher.group(1));
        if (existingLimit <= DEFAULT_LIMIT) {
            return query;
        }

        String newOuterRegion = LIMIT_PATTERN.matcher(outerRegion).replaceFirst('LIMIT ' + DEFAULT_LIMIT);
        return query.substring(0, searchFrom) + newOuterRegion;
    }
}
