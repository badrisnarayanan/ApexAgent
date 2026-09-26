@IsTest
private class ApexAgentSearchObjectsTest {

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
            Assert.isTrue(r.containsKey('qualifiedApiName'), 'Each result must have qualifiedApiName');
            Assert.isTrue(r.containsKey('label'), 'Each result must have label');
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
        ApexAgentSearchObjects.Input inp = new ApexAgentSearchObjects.Input();
        inp.searchTerm = searchTerm;
        List<ApexAgentSearchObjects.Output> results = ApexAgentSearchObjects.run(new List<ApexAgentSearchObjects.Input>{ inp });
        return (List<Object>) JSON.deserializeUntyped(JSON.serialize(results[0].results));
    }

    private static String qualifiedApiName(Object rawResult) {
        return (String) ((Map<String, Object>) rawResult).get('qualifiedApiName');
    }

    // ─── Word-overlap scoring and camelCase API names ────────────────────────────

    @IsTest
    static void testCamelCaseNamesAndUndilutedScores() {
        List<Object> lineItem = search('OpportunityLineItem');
        Assert.areEqual('OpportunityLineItem', qualifiedApiName(lineItem[0]), 'camelCase API name should be the top match');

        // 100 exact + 60 starts-with + 30 contains + 40 word overlap + 20 similarity: the
        // overlap must not be diluted by guessed sub-word fragments
        Assert.isTrue((Double) ((Map<String, Object>) lineItem[0]).get('score') >= 249.9,
            'Exact match should earn the full word-overlap points — got: ' + lineItem[0]);

        List<Object> spaced = search('opportunity line item');
        Assert.areEqual('OpportunityLineItem', qualifiedApiName(spaced[0]), 'Spaced words should find the camelCase object');

        List<Object> account = search('Account');
        Assert.areEqual('Account', qualifiedApiName(account[0]), 'Account exact match first');
        Assert.isTrue((Double) ((Map<String, Object>) account[0]).get('score') >= 249.9,
            'Single-word exact match should be undiluted — got: ' + account[0]);
    }
}
