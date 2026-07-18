@IsTest
private class QueryRecordsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInvalidInput() {
        QueryRecords tool = new QueryRecords();

        // null input
        try {
            tool.execute(null);
            Assert.fail('Expected exception for null input');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('null'), 'Message should mention null');
        }

        // missing soqlQuery key
        try {
            tool.execute(new Map<String, Object>());
            Assert.fail('Expected exception for missing soqlQuery');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('soqlQuery'), 'Message should mention soqlQuery');
        }

        // null soqlQuery value
        try {
            tool.execute(new Map<String, Object>{ 'soqlQuery' => null });
            Assert.fail('Expected exception for null soqlQuery');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('soqlQuery'), 'Message should mention soqlQuery');
        }

        // blank soqlQuery
        try {
            tool.execute(new Map<String, Object>{ 'soqlQuery' => '   ' });
            Assert.fail('Expected exception for blank soqlQuery');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }
    }

    // ─── Sanitization ────────────────────────────────────────────────────────────

    @IsTest
    static void testSanitization() {
        QueryRecords tool = new QueryRecords();

        // Whitespace + trailing semicolon stripped, default LIMIT 50 appended
        String q1 = tool.sanitize('  SELECT Id FROM Account ;  ');
        Assert.isTrue(q1.equalsIgnoreCase('SELECT Id FROM Account LIMIT 50'),
            'Should trim whitespace, remove semicolon, and add default LIMIT — got: ' + q1);

        // WITH SECURITY_ENFORCED removed (mixed case)
        String q2 = tool.sanitize('SELECT Id FROM Account WITH Security_Enforced');
        Assert.isFalse(q2.containsIgnoreCase('SECURITY_ENFORCED'),
            'WITH SECURITY_ENFORCED should be removed — got: ' + q2);
        Assert.isTrue(q2.containsIgnoreCase('LIMIT 50'), 'Default LIMIT should be added');

        // Existing LIMIT above 50 → replaced with 50
        String q3 = tool.sanitize('SELECT Id FROM Account LIMIT 200');
        Assert.isTrue(q3.containsIgnoreCase('LIMIT 50'),
            'LIMIT above 50 should be capped — got: ' + q3);
        Assert.isFalse(q3.containsIgnoreCase('LIMIT 200'), 'Original high LIMIT should be gone');

        // Existing LIMIT at 50 → unchanged
        String q4 = tool.sanitize('SELECT Id FROM Account LIMIT 50');
        Assert.isTrue(q4.containsIgnoreCase('LIMIT 50'), 'LIMIT 50 should be preserved');

        // Existing LIMIT below 50 → unchanged
        String q5 = tool.sanitize('SELECT Id FROM Account LIMIT 10');
        Assert.isTrue(q5.containsIgnoreCase('LIMIT 10'),
            'LIMIT below 50 should be left as-is — got: ' + q5);

        // Aggregate query with COUNT — LIMIT is now injected too (SOQL aggregates accept
        // LIMIT; previously aggregate detection skipped limit enforcement entirely)
        String q6 = tool.sanitize('SELECT COUNT(Id) FROM Account');
        Assert.isTrue(q6.containsIgnoreCase('LIMIT 50'),
            'Aggregate query should now have the default LIMIT added — got: ' + q6);

        // Aggregate query with GROUP BY — LIMIT is added
        String q7 = tool.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName');
        Assert.isTrue(q7.containsIgnoreCase('LIMIT 50'),
            'GROUP BY query should now have the default LIMIT added — got: ' + q7);

        // Aggregate query that already has its own LIMIT above 50 — still capped
        String q8 = tool.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName LIMIT 200');
        Assert.isTrue(q8.containsIgnoreCase('LIMIT 50'), 'Aggregate LIMIT above 50 should be capped — got: ' + q8);
        Assert.isFalse(q8.containsIgnoreCase('LIMIT 200'), 'Original high aggregate LIMIT should be gone');
    }

    // ─── Subquery LIMIT must never be mistaken for the outer query's LIMIT ────────

    @IsTest
    static void testSubqueryLimitIsNotConfusedWithOuterLimit() {
        QueryRecords tool = new QueryRecords();

        // Subquery has an oversized LIMIT (200) and the outer query has none — the
        // outer query must get the default LIMIT appended, and the subquery's own
        // LIMIT must be left completely untouched (200, not capped to 50) since it
        // governs a child relationship, not top-level record count.
        String q1 = tool.sanitize(
            'SELECT Id, (SELECT Id FROM Contacts LIMIT 200) FROM Account'
        );
        Assert.isTrue(q1.containsIgnoreCase('LIMIT 200'),
            'Subquery LIMIT 200 must be left untouched — got: ' + q1);
        Integer outerLimitCount = countOccurrences(q1.toUpperCase(), 'LIMIT 50');
        Assert.areEqual(1, outerLimitCount, 'Outer query must get exactly one default LIMIT 50 — got: ' + q1);

        // Subquery has a small LIMIT, outer query has an oversized LIMIT that must be
        // capped — the subquery's LIMIT must not be the one that gets rewritten.
        String q2 = tool.sanitize(
            'SELECT Id, (SELECT Id FROM Contacts LIMIT 5) FROM Account LIMIT 500'
        );
        Assert.isTrue(q2.containsIgnoreCase('LIMIT 5)'),
            'Subquery LIMIT 5 must be left untouched — got: ' + q2);
        Assert.isTrue(q2.toUpperCase().endsWith('LIMIT 50'),
            'Outer LIMIT 500 must be capped to 50 at the end of the query — got: ' + q2);
        Assert.isFalse(q2.containsIgnoreCase('LIMIT 500'), 'Original high outer LIMIT should be gone');
    }

    private static Integer countOccurrences(String haystack, String needle) {
        Integer count = 0;
        Integer idx = haystack.indexOf(needle);
        while (idx != -1) {
            count++;
            idx = haystack.indexOf(needle, idx + needle.length());
        }
        return count;
    }

    // ─── Successful query ────────────────────────────────────────────────────────

    @IsTest
    static void testSuccessfulQuery() {
        Account acc = new Account(Name = 'QueryRecordsTest Account');
        insert acc;

        QueryRecords tool = new QueryRecords();
        Map<String, Object> result = (Map<String, Object>) tool.execute(new Map<String, Object>{
            'soqlQuery' => 'SELECT Id, Name FROM Account WHERE Name = \'QueryRecordsTest Account\''
        });

        Assert.isTrue(result.containsKey('query'), 'Result should contain query key');
        Assert.isTrue(result.containsKey('recordCount'), 'Result should contain recordCount key');
        Assert.isTrue(result.containsKey('records'), 'Result should contain records key');
        Assert.isFalse(result.containsKey('exception'), 'Successful result should not have exception key');

        Integer count = (Integer) result.get('recordCount');
        Assert.isTrue(count >= 1, 'recordCount should be at least 1');

        List<SObject> records = (List<SObject>) result.get('records');
        Assert.isTrue(records.size() >= 1, 'records list should be non-empty');

        // Verify sanitized query is reflected
        String returnedQuery = (String) result.get('query');
        Assert.isTrue(returnedQuery.containsIgnoreCase('LIMIT'), 'Returned query should include LIMIT clause');
    }

    // ─── Invalid SOQL returns exception map ──────────────────────────────────────

    @IsTest
    static void testInvalidSoql() {
        QueryRecords tool = new QueryRecords();
        Map<String, Object> result = (Map<String, Object>) tool.execute(new Map<String, Object>{
            'soqlQuery' => 'SELECT @@INVALID@@ FROM Account'
        });

        Assert.isTrue(result.containsKey('exception'), 'Bad SOQL should return exception key');
        Assert.isFalse(result.containsKey('records'), 'Bad SOQL should not return records key');
        Assert.isTrue(result.containsKey('query'), 'Result should still include the query key');
        Assert.isTrue(String.isNotBlank((String) result.get('exception')),
            'exception message should not be blank');
    }
}
