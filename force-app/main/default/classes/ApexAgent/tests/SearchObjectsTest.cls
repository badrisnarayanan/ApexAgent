@IsTest
private class SearchObjectsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInvalidInput() {
        try {
            search(null);
            Assert.fail('Expected exception for null searchTerm');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().toLowerCase().contains('blank'), 'Message should mention blank');
        }

        try {
            search('   ');
            Assert.fail('Expected exception for blank searchTerm');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().toLowerCase().contains('blank'), 'Message should mention blank');
        }
    }

    // ─── Result structure ────────────────────────────────────────────────────────

    @IsTest
    static void testResultStructureAndOrdering() {
        List<Object> results = search('account');

        Assert.isNotNull(results, 'Results should not be null');
        Assert.isTrue(results.size() > 0, 'Should return at least one result for "account"');
        Assert.isTrue(results.size() <= 10, 'Should return at most 10 results');

        Double prevScore = 9999999;
        for (Object raw : results) {
            Map<String, Object> r = (Map<String, Object>) raw;
            Assert.isTrue(r.containsKey('QualifiedApiName'), 'Each result must have QualifiedApiName');
            Assert.isTrue(r.containsKey('Label'), 'Each result must have Label');
            Assert.isTrue(r.containsKey('score'), 'Each result must have score');
            Double score = (Double) r.get('score');
            Assert.isTrue(score > 0, 'Score must be positive');
            Assert.isTrue(score <= prevScore, 'Results must be in descending score order');
            prevScore = score;
        }
    }

    // ─── Well-known terms return correct top matches ─────────────────────────────

    @IsTest
    static void testKnownTerms() {
        List<Object> caseResults = search('case');
        Assert.isTrue(caseResults.size() > 0, '"case" should return results');
        Assert.areEqual('Case', qualifiedApiName(caseResults[0]), '"case" top result should be Case');

        List<Object> accResults = search('account');
        Assert.isTrue(accResults.size() > 0, '"account" should return results');
        Assert.isTrue(qualifiedApiName(accResults[0]).toLowerCase().contains('account'), '"account" top result should contain account');

        List<Object> contactResults = search('contact');
        Assert.isTrue(contactResults.size() > 0, '"contact" should return results');
        Assert.isTrue(qualifiedApiName(contactResults[0]).toLowerCase().contains('contact'), '"contact" top result should contain contact');
    }

    // ─── Abbreviation expansion ──────────────────────────────────────────────────

    @IsTest
    static void testAbbreviations() {
        List<Object> accResults = search('acc');
        Assert.isTrue(accResults.size() > 0, '"acc" should return results');
        Boolean foundAccount = false;
        for (Object r : accResults) {
            if (qualifiedApiName(r).equalsIgnoreCase('Account')) {
                foundAccount = true;
                break;
            }
        }
        Assert.isTrue(foundAccount, '"acc" should include Account in results');

        List<Object> woResults = search('wo');
        Assert.isTrue(woResults.size() > 0, '"wo" should return results');
        Boolean foundWorkOrder = false;
        for (Object r : woResults) {
            if (qualifiedApiName(r).equalsIgnoreCase('WorkOrder')) {
                foundWorkOrder = true;
                break;
            }
        }
        Assert.isTrue(foundWorkOrder, '"wo" should include WorkOrder in results');
    }

    // ─── Multi-word and camelCase terms ──────────────────────────────────────────

    @IsTest
    static void testMultiWordAndCamelCase() {
        List<Object> woResults = search('work order');
        Assert.isTrue(woResults.size() > 0, '"work order" should return results');
        String topWo = qualifiedApiName(woResults[0]).toLowerCase();
        Assert.isTrue(topWo.contains('workorder') || topWo.contains('work'),
            '"work order" top result should relate to WorkOrder');

        List<Object> ccResults = search('WorkOrder');
        Assert.isTrue(ccResults.size() > 0, '"WorkOrder" should return results');
        Assert.isTrue(
            qualifiedApiName(ccResults[0]).equalsIgnoreCase('WorkOrder'),
            '"WorkOrder" camelCase top result should be WorkOrder'
        );
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static List<Object> search(String searchTerm) {
        SearchObjects.Input inp = new SearchObjects.Input();
        inp.searchTerm = searchTerm;
        List<SearchObjects.Output> results = SearchObjects.run(new List<SearchObjects.Input>{ inp });
        return (List<Object>) JSON.deserializeUntyped(results[0].resultJson);
    }

    private static String qualifiedApiName(Object rawResult) {
        return (String) ((Map<String, Object>) rawResult).get('QualifiedApiName');
    }
}
