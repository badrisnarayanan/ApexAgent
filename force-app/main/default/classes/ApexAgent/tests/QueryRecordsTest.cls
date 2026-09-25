@IsTest
private class QueryRecordsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInvalidInput() {
        try {
            run('   ');
            Assert.fail('Expected exception for blank soqlQuery');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }
    }

    // ─── Sanitization ────────────────────────────────────────────────────────────

    @IsTest
    static void testSanitization() {
        // Whitespace + trailing semicolon stripped, default LIMIT 50 appended
        String q1 = QueryRecords.sanitize('  SELECT Id FROM Account ;  ');
        Assert.isTrue(q1.equalsIgnoreCase('SELECT Id FROM Account LIMIT 50'),
            'Should trim whitespace, remove semicolon, and add default LIMIT — got: ' + q1);

        // WITH SECURITY_ENFORCED removed (mixed case)
        String q2 = QueryRecords.sanitize('SELECT Id FROM Account WITH Security_Enforced');
        Assert.isFalse(q2.containsIgnoreCase('SECURITY_ENFORCED'),
            'WITH SECURITY_ENFORCED should be removed — got: ' + q2);
        Assert.isTrue(q2.containsIgnoreCase('LIMIT 50'), 'Default LIMIT should be added');

        // Existing LIMIT above 50 → replaced with 50
        String q3 = QueryRecords.sanitize('SELECT Id FROM Account LIMIT 200');
        Assert.isTrue(q3.containsIgnoreCase('LIMIT 50'),
            'LIMIT above 50 should be capped — got: ' + q3);
        Assert.isFalse(q3.containsIgnoreCase('LIMIT 200'), 'Original high LIMIT should be gone');

        // Existing LIMIT at 50 → unchanged
        String q4 = QueryRecords.sanitize('SELECT Id FROM Account LIMIT 50');
        Assert.isTrue(q4.containsIgnoreCase('LIMIT 50'), 'LIMIT 50 should be preserved');

        // Existing LIMIT below 50 → unchanged
        String q5 = QueryRecords.sanitize('SELECT Id FROM Account LIMIT 10');
        Assert.isTrue(q5.containsIgnoreCase('LIMIT 10'),
            'LIMIT below 50 should be left as-is — got: ' + q5);

        // Plain aggregates (no GROUP BY) are left exactly as written — no LIMIT added or capped
        String q6 = QueryRecords.sanitize('SELECT COUNT(Id) FROM Account');
        Assert.areEqual('SELECT COUNT(Id) FROM Account', q6, 'COUNT query must not get a LIMIT');
        Assert.areEqual('SELECT COUNT() FROM Account WHERE Name = \'x\' LIMIT 500',
            QueryRecords.sanitize('SELECT COUNT() FROM Account WHERE Name = \'x\' LIMIT 500'), 'plain aggregate keeps its own LIMIT');

        // GROUP BY can return up to 2000 rows, so it is capped at 200 rather than 50
        Assert.areEqual('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName LIMIT 200',
            QueryRecords.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName;'), 'GROUP BY gets 200');
        Assert.areEqual('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName LIMIT 200',
            QueryRecords.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName LIMIT 900'), 'GROUP BY LIMIT above 200 is capped');
        Assert.areEqual('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName LIMIT 120',
            QueryRecords.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName LIMIT 120'), 'GROUP BY LIMIT up to 200 is kept');
        Assert.areEqual('SELECT Type FROM Account GROUP BY Type LIMIT 200',
            QueryRecords.sanitize('SELECT Type FROM Account GROUP BY Type'), 'GROUP BY without an aggregate function');
        Assert.areEqual('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName HAVING COUNT(Id) > 1 ORDER BY COUNT(Id) DESC LIMIT 200',
            QueryRecords.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName HAVING COUNT(Id) > 1 ORDER BY COUNT(Id) DESC'),
            'LIMIT goes after HAVING / ORDER BY, whose parentheses must not confuse the boundary');
        Assert.areEqual('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName LIMIT 200 OFFSET 5',
            QueryRecords.sanitize('SELECT StageName, COUNT(Id) FROM Opportunity GROUP BY StageName OFFSET 5'), 'GROUP BY + OFFSET');

        // Zero-padded and zero LIMITs are read as their numeric value
        Assert.areEqual('SELECT Id FROM Account LIMIT 0000000000010',
            QueryRecords.sanitize('SELECT Id FROM Account LIMIT 0000000000010'), 'zero-padded small LIMIT is kept');
        Assert.areEqual('SELECT Id FROM Account LIMIT 0', QueryRecords.sanitize('SELECT Id FROM Account LIMIT 0'), 'LIMIT 0 is kept');

        // A subquery's aggregate does not make the outer query an aggregate
        String q9 = QueryRecords.sanitize('SELECT Id, (SELECT COUNT() FROM Contacts) FROM Account');
        Assert.isTrue(q9.endsWith('LIMIT 50'), 'Non-aggregate outer query must still be limited — got: ' + q9);
    }

    // ─── Subquery LIMIT must never be mistaken for the outer query's LIMIT ────────

    @IsTest
    static void testSubqueryLimitIsNotConfusedWithOuterLimit() {
        // Subquery has an oversized LIMIT (200) and the outer query has none — the
        // outer query must get the default LIMIT appended, and the subquery's own
        // LIMIT must be left completely untouched (200, not capped to 50) since it
        // governs a child relationship, not top-level record count.
        String q1 = QueryRecords.sanitize(
            'SELECT Id, (SELECT Id FROM Contacts LIMIT 200) FROM Account'
        );
        Assert.isTrue(q1.containsIgnoreCase('LIMIT 200'),
            'Subquery LIMIT 200 must be left untouched — got: ' + q1);
        Integer outerLimitCount = countOccurrences(q1.toUpperCase(), 'LIMIT 50');
        Assert.areEqual(1, outerLimitCount, 'Outer query must get exactly one default LIMIT 50 — got: ' + q1);

        // Subquery has a small LIMIT, outer query has an oversized LIMIT that must be
        // capped — the subquery's LIMIT must not be the one that gets rewritten.
        String q2 = QueryRecords.sanitize(
            'SELECT Id, (SELECT Id FROM Contacts LIMIT 5) FROM Account LIMIT 500'
        );
        Assert.isTrue(q2.containsIgnoreCase('LIMIT 5)'),
            'Subquery LIMIT 5 must be left untouched — got: ' + q2);
        Assert.isTrue(q2.toUpperCase().endsWith('LIMIT 50'),
            'Outer LIMIT 500 must be capped to 50 at the end of the query — got: ' + q2);
        Assert.isFalse(q2.containsIgnoreCase('LIMIT 500'), 'Original high outer LIMIT should be gone');
    }

    // ─── Default LIMIT goes before trailing OFFSET / FOR / ALL ROWS clauses ──────

    @IsTest
    static void testDefaultLimitPrecedesTrailingClauses() {
        Assert.areEqual('SELECT Id FROM Account ORDER BY Id LIMIT 50 OFFSET 10',
            QueryRecords.sanitize('SELECT Id FROM Account ORDER BY Id OFFSET 10'), 'OFFSET');
        Assert.areEqual('SELECT Id FROM Account LIMIT 50 for view',
            QueryRecords.sanitize('SELECT Id FROM Account for view;'), 'lowercase FOR VIEW with semicolon');
        Assert.areEqual('SELECT Id FROM Account LIMIT 50 FOR UPDATE',
            QueryRecords.sanitize('SELECT Id FROM Account FOR UPDATE'), 'FOR UPDATE');
        Assert.areEqual('SELECT Id FROM Account LIMIT 50 FOR REFERENCE UPDATE TRACKING',
            QueryRecords.sanitize('SELECT Id FROM Account FOR REFERENCE UPDATE TRACKING'), 'FOR REFERENCE');
        Assert.areEqual('SELECT Id FROM Account WHERE IsDeleted = true LIMIT 50 ALL ROWS',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE IsDeleted = true ALL ROWS'), 'ALL ROWS');
        Assert.areEqual('SELECT Id, (SELECT Id FROM Contacts) FROM Account LIMIT 50 OFFSET 5',
            QueryRecords.sanitize('SELECT Id, (SELECT Id FROM Contacts) FROM Account OFFSET 5'), 'subquery + OFFSET');

        // An existing LIMIT is still capped in place when a trailing clause follows it
        Assert.areEqual('SELECT Id FROM Account LIMIT 50 OFFSET 5',
            QueryRecords.sanitize('SELECT Id FROM Account LIMIT 500 OFFSET 5'), 'capped LIMIT + OFFSET');
    }

    // ─── String literals are never mistaken for SOQL syntax ───────────────────────

    @IsTest
    static void testStringLiteralsAreNeverRewritten() {
        // Trailing-clause keywords inside a literal: LIMIT goes at the very end, literal intact
        Assert.areEqual('SELECT Id FROM Account WHERE Name LIKE \'%Offset%\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name LIKE \'%Offset%\''), 'OFFSET in literal');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'for update\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'for update\''), 'FOR UPDATE in literal');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'all rows\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'all rows\''), 'ALL ROWS in literal');

        // A LIMIT inside a literal is neither the query's LIMIT nor rewritten
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'LIMIT 500\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'LIMIT 500\''), 'LIMIT in literal, none real');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'LIMIT 500\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'LIMIT 500\' LIMIT 500'), 'LIMIT in literal, real one capped');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'LIMIT 500\' LIMIT 10',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'LIMIT 500\' LIMIT 10'), 'LIMIT in literal, small real one kept');

        // A real trailing clause is still found after a literal that contains keywords
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'offset\' LIMIT 50 OFFSET 3',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'offset\' OFFSET 3'), 'literal then real OFFSET');

        // ')' or '(' inside a literal must not move the outer-query boundary
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'a)b\' LIMIT 50 OFFSET 3',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'a)b\' OFFSET 3'), ') in literal');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'(x\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'(x\''), '( in literal');

        // Escapes: \' keeps the literal open, \\ before the closing quote does not
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'O\\\'Brien for update\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'O\\\'Brien for update\''), 'escaped quote');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'a\\\\\' LIMIT 50 OFFSET 1',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'a\\\\\' OFFSET 1'), 'escaped backslash then closing quote');

        // Aggregate keywords inside a literal do not make the query an aggregate
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'COUNT(x\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'COUNT(x\''), 'COUNT( in literal');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'group by\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'group by\''), 'GROUP BY in literal');
        Assert.areEqual('SELECT COUNT(Id) FROM Account WHERE Name = \'x\'',
            QueryRecords.sanitize('SELECT COUNT(Id) FROM Account WHERE Name = \'x\''), 'real aggregate with a literal');

        // WITH SECURITY_ENFORCED: removed when real, kept when inside a literal
        Assert.areEqual('SELECT Id FROM Account LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WITH SECURITY_ENFORCED'), 'real SECURITY_ENFORCED');
        Assert.areEqual('SELECT Id FROM Account WHERE Name = \'with security_enforced\' LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'with security_enforced\' WITH SECURITY_ENFORCED'),
            'literal SECURITY_ENFORCED kept, real one removed');

        // An oversized LIMIT that overflows Integer is still capped
        Assert.areEqual('SELECT Id FROM Account LIMIT 50',
            QueryRecords.sanitize('SELECT Id FROM Account LIMIT 99999999999999'), 'overflowing LIMIT');

        // Unterminated literal: left alone for SOQL to reject, no exception from sanitizing
        String unterminated = QueryRecords.sanitize('SELECT Id FROM Account WHERE Name = \'oops OFFSET 3');
        Assert.isTrue(unterminated.endsWith('LIMIT 50'), 'Unterminated literal — got: ' + unterminated);

        // The mask keeps positions aligned with the original
        String q = 'SELECT Id FROM Account WHERE Name = \'a\\\'b LIMIT 5\'';
        Assert.areEqual(q.length(), QueryRecords.maskStringLiterals(q).length(), 'Mask must preserve length');

        // End to end: the query actually runs and matches the record whose name holds the keywords
        insert ApexAgentTestDataFactory.newTopic('Offset Printing for update', 'offset_printing');
        Map<String, Object> result = run('SELECT Id FROM ApexAgent_Topic__c WHERE Name LIKE \'%Offset%\'');
        Assert.isFalse(result.containsKey('error'), 'Should not error — got: ' + result.get('error'));
        Assert.areEqual(1, (Integer) result.get('recordCount'), 'Literal must reach SOQL untouched');
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
        insert ApexAgentTestDataFactory.newTopic('QueryRecordsTest Topic', 'query_records_test');

        Map<String, Object> result = run('SELECT Id, Name FROM ApexAgent_Topic__c WHERE Name = \'QueryRecordsTest Topic\'');

        Assert.isTrue(result.containsKey('query'), 'Result should contain query key');
        Assert.isTrue(result.containsKey('recordCount'), 'Result should contain recordCount key');
        Assert.isTrue(result.containsKey('records'), 'Result should contain records key');
        Assert.isFalse(result.containsKey('error'), 'Successful result should not have error key');

        Integer count = (Integer) result.get('recordCount');
        Assert.isTrue(count >= 1, 'recordCount should be at least 1');

        List<Object> records = (List<Object>) result.get('records');
        Assert.isTrue(records.size() >= 1, 'records list should be non-empty');

        // Verify sanitized query is reflected
        String returnedQuery = (String) result.get('query');
        Assert.isTrue(returnedQuery.containsIgnoreCase('LIMIT'), 'Returned query should include LIMIT clause');
    }

    // ─── SELECT COUNT() needs countQuery ─────────────────────────────────────────

    @IsTest
    static void testBareCountQuery() {
        insert new List<ApexAgent_Topic__c>{
            ApexAgentTestDataFactory.newTopic('CountTest A', 'count_test_a'),
            ApexAgentTestDataFactory.newTopic('CountTest B', 'count_test_b')
        };

        Map<String, Object> result = run('select count() from ApexAgent_Topic__c where Name like \'CountTest%\'');

        Assert.isFalse(result.containsKey('error'), 'COUNT() must not error — got: ' + result.get('error'));
        Assert.areEqual(2, (Integer) result.get('recordCount'), 'recordCount should carry the count');
        Assert.isFalse(((String) result.get('query')).containsIgnoreCase('LIMIT'), 'COUNT() must not be limited');

        // COUNT(Id) reports through records, not recordCount: the row holds the count
        Map<String, Object> countId = run('SELECT COUNT(Id) total FROM ApexAgent_Topic__c WHERE Name LIKE \'CountTest%\'');
        Assert.isFalse(countId.containsKey('error'), 'COUNT(Id) must not error — got: ' + countId.get('error'));
        Assert.areEqual(1, (Integer) countId.get('recordCount'), 'COUNT(Id) returns a single aggregate row');
        Assert.areEqual(2, (Integer) ((Map<String, Object>) ((List<Object>) countId.get('records'))[0]).get('total'),
            'The count is in the aggregate row');

        // GROUP BY runs with the 200 cap applied
        Map<String, Object> grouped = run('SELECT Name, COUNT(Id) c FROM ApexAgent_Topic__c WHERE Name LIKE \'CountTest%\' GROUP BY Name');
        Assert.isFalse(grouped.containsKey('error'), 'GROUP BY must not error — got: ' + grouped.get('error'));
        Assert.areEqual(2, (Integer) grouped.get('recordCount'), 'One group per distinct name');
        Assert.isTrue(((String) grouped.get('query')).endsWith('LIMIT 200'), 'GROUP BY gets the 200 cap');
    }

    // ─── Invalid SOQL returns an error message ──────────────────────────────────────

    @IsTest
    static void testInvalidSoql() {
        Map<String, Object> result = run('SELECT @@INVALID@@ FROM Account');

        Assert.isTrue(result.containsKey('error'), 'Bad SOQL should return error key');
        Assert.isFalse(result.containsKey('records'), 'Bad SOQL should not return records key');
        Assert.isTrue(result.containsKey('query'), 'Result should still include the query key');
        Assert.isTrue(String.isNotBlank((String) result.get('error')),
            'exception message should not be blank');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static Map<String, Object> run(String soqlQuery) {
        QueryRecords.Input inp = new QueryRecords.Input();
        inp.soqlQuery = soqlQuery;
        List<QueryRecords.Output> out = QueryRecords.run(new List<QueryRecords.Input>{ inp });
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(out[0], true));
    }
}
