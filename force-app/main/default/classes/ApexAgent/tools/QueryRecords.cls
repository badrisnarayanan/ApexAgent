public with sharing class QueryRecords implements ApexAgentTool {

    private static final Integer DEFAULT_LIMIT = 50;

    private static final Pattern LIMIT_PATTERN  = Pattern.compile('(?i)\\bLIMIT\\s+(\\d+)');
    private static final Pattern SECURITY_ENFORCED_PATTERN =
        Pattern.compile('(?i)\\bWITH\\s+SECURITY_ENFORCED\\b');

    private static final List<String> AGGREGATE_TOKENS = new List<String>{
        'group by', 'grouping(', 'count(', 'sum(', 'avg(', 'min(', 'max(', 'count_distinct('
    };

    public Object execute(Map<String, Object> input) {
        validateInput(input);

        String sanitized = sanitize(String.valueOf(input.get('soqlQuery')));

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

    // ─── Input validation ────────────────────────────────────────────────────────

    private void validateInput(Map<String, Object> input) {
        if (input == null) {
            throw new IllegalArgumentException('Input map must not be null');
        }
        if (!input.containsKey('soqlQuery') || input.get('soqlQuery') == null) {
            throw new IllegalArgumentException('Missing required input parameter: soqlQuery');
        }
        if (String.isBlank(String.valueOf(input.get('soqlQuery')))) {
            throw new IllegalArgumentException('Input parameter soqlQuery must not be blank');
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

        // 4. Aggregate detection — skip limit enforcement for aggregate queries
        if (isAggregateQuery(query)) {
            return query;
        }

        // 5 & 6. Detect and enforce LIMIT
        Matcher limitMatcher = LIMIT_PATTERN.matcher(query);
        if (limitMatcher.find()) {
            Integer existingLimit = Integer.valueOf(limitMatcher.group(1));
            if (existingLimit > DEFAULT_LIMIT) {
                query = LIMIT_PATTERN.matcher(query).replaceFirst('LIMIT ' + DEFAULT_LIMIT);
            }
        } else {
            query = query + ' LIMIT ' + DEFAULT_LIMIT;
        }

        return query;
    }

    private Boolean isAggregateQuery(String query) {
        String lower = query.toLowerCase();
        for (String token : AGGREGATE_TOKENS) {
            if (lower.contains(token)) {
                return true;
            }
        }
        return false;
    }
}
