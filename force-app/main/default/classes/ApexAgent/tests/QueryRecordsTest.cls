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

        // Aggregate query with COUNT — no LIMIT injected
        String q6 = tool.sanitize('SELECT COUNT(Id) FROM Account');
        Assert.isFalse(q6.containsIgnoreCase('LIMIT'),
            'Aggregate query should not have LIMIT added — got: ' + q6);

        // Aggregate query with GROUP BY — no LIMIT injected
        String q7 = tool.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName');
        Assert.isFalse(q7.containsIgnoreCase('LIMIT'),
            'GROUP BY query should not have LIMIT added — got: ' + q7);

        // Aggregate query with GROUPING() — no LIMIT injected
        String q8 = tool.sanitize('SELECT GROUPING(StageName) FROM Opportunity GROUP BY ROLLUP(StageName)');
        Assert.isFalse(q8.containsIgnoreCase('LIMIT'),
            'GROUPING() query should not have LIMIT added — got: ' + q8);
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
