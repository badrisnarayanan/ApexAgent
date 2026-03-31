@IsTest
private class SearchObjectsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInvalidInput() {
        SearchObjects tool = new SearchObjects();

        // null input
        try {
            tool.execute(null);
            Assert.fail('Expected exception for null input');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('searchTerm'), 'Message should mention searchTerm');
        }

        // missing searchTerm key
        try {
            tool.execute(new Map<String, Object>{ 'foo' => 'bar' });
            Assert.fail('Expected exception for missing searchTerm key');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('searchTerm'), 'Message should mention searchTerm');
        }

        // null searchTerm value
        try {
            tool.execute(new Map<String, Object>{ 'searchTerm' => null });
            Assert.fail('Expected exception for null searchTerm');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().toLowerCase().contains('null'), 'Message should mention null');
        }

        // blank searchTerm
        try {
            tool.execute(new Map<String, Object>{ 'searchTerm' => '   ' });
            Assert.fail('Expected exception for blank searchTerm');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().toLowerCase().contains('blank'), 'Message should mention blank');
        }
    }

    // ─── Result structure ────────────────────────────────────────────────────────

    @IsTest
    static void testResultStructureAndOrdering() {
        SearchObjects tool = new SearchObjects();
        List<Map<String, Object>> results = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'account' }
        );

        Assert.isNotNull(results, 'Results should not be null');
        Assert.isTrue(results.size() > 0, 'Should return at least one result for "account"');
        Assert.isTrue(results.size() <= 10, 'Should return at most 10 results');

        // Every result must have required keys
        for (Map<String, Object> r : results) {
            Assert.isTrue(r.containsKey('QualifiedApiName'), 'Each result must have QualifiedApiName');
            Assert.isTrue(r.containsKey('Label'), 'Each result must have Label');
            Assert.isTrue(r.containsKey('score'), 'Each result must have score');
            Assert.isTrue((Double) r.get('score') > 0, 'Score must be positive');
        }

        // Results must be in descending score order
        Double prevScore = 9999999;
        for (Map<String, Object> r : results) {
            Double score = (Double) r.get('score');
            Assert.isTrue(score <= prevScore, 'Results must be in descending score order');
            prevScore = score;
        }
    }

    // ─── Well-known terms return correct top matches ─────────────────────────────

    @IsTest
    static void testKnownTerms() {
        SearchObjects tool = new SearchObjects();

        // "case" — exact match expected
        List<Map<String, Object>> caseResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'case' }
        );
        Assert.isTrue(caseResults.size() > 0, '"case" should return results');
        String topCase = (String) caseResults[0].get('QualifiedApiName');
        Assert.areEqual('Case', topCase, '"case" top result should be Case');

        // "account" — exact match expected
        List<Map<String, Object>> accResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'account' }
        );
        Assert.isTrue(accResults.size() > 0, '"account" should return results');
        String topAcc = (String) accResults[0].get('QualifiedApiName');
        Assert.isTrue(topAcc.toLowerCase().contains('account'), '"account" top result should contain account');

        // "contact" — exact match expected
        List<Map<String, Object>> contactResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'contact' }
        );
        Assert.isTrue(contactResults.size() > 0, '"contact" should return results');
        String topContact = (String) contactResults[0].get('QualifiedApiName');
        Assert.isTrue(topContact.toLowerCase().contains('contact'), '"contact" top result should contain contact');
    }

    // ─── Abbreviation expansion ──────────────────────────────────────────────────

    @IsTest
    static void testAbbreviations() {
        SearchObjects tool = new SearchObjects();

        // "acc" → should score Account highly
        List<Map<String, Object>> accResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'acc' }
        );
        Assert.isTrue(accResults.size() > 0, '"acc" should return results');
        Boolean foundAccount = false;
        for (Map<String, Object> r : accResults) {
            if (String.valueOf(r.get('QualifiedApiName')).equalsIgnoreCase('Account')) {
                foundAccount = true;
                break;
            }
        }
        Assert.isTrue(foundAccount, '"acc" should include Account in results');

        // "wo" → should score WorkOrder highly
        List<Map<String, Object>> woResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'wo' }
        );
        Assert.isTrue(woResults.size() > 0, '"wo" should return results');
        Boolean foundWorkOrder = false;
        for (Map<String, Object> r : woResults) {
            if (String.valueOf(r.get('QualifiedApiName')).equalsIgnoreCase('WorkOrder')) {
                foundWorkOrder = true;
                break;
            }
        }
        Assert.isTrue(foundWorkOrder, '"wo" should include WorkOrder in results');
    }

    // ─── Multi-word and camelCase terms ──────────────────────────────────────────

    @IsTest
    static void testMultiWordAndCamelCase() {
        SearchObjects tool = new SearchObjects();

        // "work order" (space-separated)
        List<Map<String, Object>> woResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'work order' }
        );
        Assert.isTrue(woResults.size() > 0, '"work order" should return results');
        String topWo = (String) woResults[0].get('QualifiedApiName');
        Assert.isTrue(topWo.toLowerCase().contains('workorder') || topWo.toLowerCase().contains('work'),
            '"work order" top result should relate to WorkOrder');

        // "WorkOrder" (camelCase)
        List<Map<String, Object>> ccResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'WorkOrder' }
        );
        Assert.isTrue(ccResults.size() > 0, '"WorkOrder" should return results');
        Assert.isTrue(
            String.valueOf(ccResults[0].get('QualifiedApiName')).equalsIgnoreCase('WorkOrder'),
            '"WorkOrder" camelCase top result should be WorkOrder'
        );
    }
}
