/**
 * Apex Action tool: runs an LLM-supplied SOQL query with a default row limit.
 *
 * Not bulk-mergeable: each input carries an independent, arbitrary query string,
 * so there is no shared key to group on the way GetRecordDetails groups by object
 * type. ApexAgentToolExecutor only ever invokes this action with a single input.
 */
public with sharing class QueryRecords {

    private static final Integer DEFAULT_LIMIT = 50;

    private static final Pattern LIMIT_PATTERN  = Pattern.compile('(?i)\\bLIMIT\\s+(\\d+)');
    private static final Pattern SECURITY_ENFORCED_PATTERN =
        Pattern.compile('(?i)\\bWITH\\s+SECURITY_ENFORCED\\b');

    public class Input {
        @InvocableVariable(required=true label='SOQL Query' description='The SOQL query to execute. A default LIMIT of 50 is applied if none is specified.')
        public String soqlQuery;
    }

    public class Output {
        @InvocableVariable(label='Result' description='JSON object with the sanitized query, record count, and records (or a query exception message).')
        public String resultJson;
    }

    @InvocableMethod(label='Query Records' description='Executes a SOQL query and returns matching records. Automatically caps results at 50 records (lower limits are respected, higher limits are reduced to 50). Aggregate queries are also supported\n\nCritical usage rules:\n- Always construct a valid SOQL query first based on the user\'s request, then pass it to this tool for execution.\n- If the object name is unfamiliar, use SearchObjects first to confirm it exists and get its exact API name.\n- Always use GetObjectDetails first (if not already called) to discover available fields on the object. Use GetFieldDetails if you need deeper field metadata before building your query. Never guess field names.\n\nWhen not to use:\n- You need fuzzy name search within one object → use SearchRecords.\n- You need a single record by ID → use GetRecordDetails.')
    public static List<Output> run(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(processOne(inp));
        }
        return results;
    }

    private static Output processOne(Input inp) {
        String soqlQuery = ApexAgentToolInput.requireNotBlank(inp.soqlQuery, 'soqlQuery');
        String sanitized = sanitize(soqlQuery);

        Output o = new Output();
        try {
            List<SObject> records = Database.query(sanitized, System.AccessLevel.USER_MODE);
            o.resultJson = JSON.serialize(new Map<String, Object>{
                'query'       => sanitized,
                'recordCount' => records.size(),
                'records'     => records
            });
        } catch (QueryException e) {
            o.resultJson = JSON.serialize(new Map<String, Object>{
                'query'     => sanitized,
                'exception' => e.getMessage()
            });
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
    private static String enforceLimit(String query) {
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
