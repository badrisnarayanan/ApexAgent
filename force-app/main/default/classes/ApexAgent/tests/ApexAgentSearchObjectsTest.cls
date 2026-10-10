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

    // ─── Well-known terms return the matching standard object ────────────────────
    // Object metadata is not isolated in tests, so an installing org's own or packaged
    // objects are ranked too and one labelled the same can tie with the standard object.
    // These tests assert the object is returned, never that it is first.

    @IsTest
    static void testKnownTerms() {
        Assert.isNotNull(resultFor(search('case'), 'Case'), '"case" should return Case');
        Assert.isNotNull(resultFor(search('account'), 'Account'), '"account" should return Account');
        Assert.isNotNull(resultFor(search('contact'), 'Contact'), '"contact" should return Contact');
    }

    // ─── Abbreviation expansion ──────────────────────────────────────────────────

    @IsTest
    static void testAbbreviations() {
        Assert.isNotNull(resultFor(search('acc'), 'Account'), '"acc" should include Account in results');
        Assert.isNotNull(resultFor(search('wo'), 'WorkOrder'), '"wo" should include WorkOrder in results');
    }

    // ─── Multi-word and camelCase terms ──────────────────────────────────────────

    @IsTest
    static void testMultiWordAndCamelCase() {
        Assert.isNotNull(resultFor(search('work order'), 'WorkOrder'), '"work order" should return WorkOrder');
        Assert.isNotNull(resultFor(search('WorkOrder'), 'WorkOrder'), '"WorkOrder" camelCase should return WorkOrder');
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

    private static Map<String, Object> resultFor(List<Object> results, String apiName) {
        for (Object raw : results) {
            if (qualifiedApiName(raw).equalsIgnoreCase(apiName)) {
                return (Map<String, Object>) raw;
            }
        }
        return null;
    }

    // ─── Word-overlap scoring and camelCase API names ────────────────────────────

    @IsTest
    static void testCamelCaseNamesAndUndilutedScores() {
        Map<String, Object> lineItem = resultFor(search('OpportunityLineItem'), 'OpportunityLineItem');
        Assert.isNotNull(lineItem, 'camelCase API name should be found');

        // 100 exact + 60 starts-with + 30 contains + 40 word overlap + 20 similarity: the
        // overlap must not be diluted by guessed sub-word fragments
        Assert.isTrue((Double) lineItem.get('score') >= 249.9,
            'Exact match should earn the full word-overlap points — got: ' + lineItem);

        Assert.isNotNull(resultFor(search('opportunity line item'), 'OpportunityLineItem'),
            'Spaced words should find the camelCase object');

        Map<String, Object> account = resultFor(search('Account'), 'Account');
        Assert.isNotNull(account, 'Account should be found by its exact name');
        Assert.isTrue((Double) account.get('score') >= 249.9,
            'Single-word exact match should be undiluted — got: ' + account);
    }

    // ─── An exact match survives the candidate queries being cut short ───────────

    @IsTest
    static void testExactMatchSurvivesTruncatedCandidates() {
        // Far more than one object matches "account", so a limit of 1 cuts both
        // candidate queries short, as 200 does in an org with enough objects
        ApexAgentSearchObjects.candidateLimit = 1;

        Map<String, Object> account = resultFor(search('account'), 'Account');
        Assert.isNotNull(account, 'The object named outright must be found even when the candidates are cut short');
        Assert.isTrue((Double) account.get('score') >= 249.9, 'It should still score as an exact match — got: ' + account);
        Assert.isNotNull(resultFor(search('work order'), 'WorkOrder'), 'An exact label match must be found too');
    }

    // ─── Equal scores are ordered standard, then the org's own, then packaged ────

    @IsTest
    static void testTiesPreferStandardThenOwnThenPackagedObjects() {
        // Same label on all four, so every score is identical. Built out of order.
        Map<String, EntityDefinition> candidates = new Map<String, EntityDefinition>();
        for (String apiName : new List<String>{ 'pkg__Account__c', 'Account_Record__c', 'Account__c', 'Account' }) {
            candidates.put(apiName, (EntityDefinition) JSON.deserialize(
                JSON.serialize(new Map<String, Object>{ 'QualifiedApiName' => apiName, 'Label' => 'Account' }), EntityDefinition.class));
        }

        List<ApexAgentSearchObjects.ObjectMatch> ranked = ApexAgentSearchObjects.scoreAndRank(candidates, 'account');

        Assert.areEqual(4, ranked.size(), 'Every candidate should be ranked');
        Assert.areEqual(ranked[0].score, ranked[3].score, 'The candidates are meant to tie — got: ' + ranked);
        Assert.areEqual('Account', ranked[0].qualifiedApiName, 'The standard object goes first');
        Assert.areEqual('Account__c', ranked[1].qualifiedApiName, 'The shorter of the org\'s own objects goes next');
        Assert.areEqual('Account_Record__c', ranked[2].qualifiedApiName, 'The org\'s own objects go before packaged ones');
        Assert.areEqual('pkg__Account__c', ranked[3].qualifiedApiName, 'Packaged objects go last');
    }
}
