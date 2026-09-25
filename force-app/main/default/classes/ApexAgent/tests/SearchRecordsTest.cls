@isTest
private class SearchRecordsTest {

    // ─── Test data ────────────────────────────────────────────────────────────────

    @testSetup
    static void setup() {
        ApexAgent_LLM__c llm = ApexAgentTestDataFactory.newLlm('SearchRecordsTest LLM');
        insert llm;
        // Company-style and person-style names on one searchable package object, so the
        // subscriber org's own automation on standard objects can't affect the setup
        insert newAgents(new List<String>{
            'Acme Inc', 'Acme Corp', 'Acme Technologies', 'Global Solutions LLC',
            'TechNova Group Holdings', 'My Acme Partner',
            // Diverse company formats for edge-case testing
            'IBM Global Services', '3M Corporation', 'Smith-Jones Consulting',
            'QuickBooks Online', 'Salesforce Inc',
            // Person names
            'John Smith', 'Jane Doe', 'Alice Johnson', 'John Adams', 'Smith Williams',
            // Diverse person name formats
            'Raj Kumar', 'Mary O\'Brien', 'Jean-Pierre Dupont'
        });
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static final String AGENT_OBJECT = 'ApexAgent_Agent__c';

    private static List<ApexAgent_Agent__c> newAgents(List<String> names) {
        Id llmId = [SELECT Id FROM ApexAgent_LLM__c LIMIT 1].Id;
        List<ApexAgent_Agent__c> agents = new List<ApexAgent_Agent__c>();
        for (String name : names) {
            agents.add(ApexAgentTestDataFactory.newAgent(name, llmId));
        }
        return agents;
    }

    private static ApexAgent_Agent__c agentNamed(String name) {
        return [SELECT Id FROM ApexAgent_Agent__c WHERE Name = :name LIMIT 1];
    }

    private static List<Map<String, Object>> search(String searchTerm, String objectApiName) {
        SearchRecords.Input inp = new SearchRecords.Input();
        inp.searchTerm = searchTerm;
        inp.objectApiName = objectApiName;
        List<SearchRecords.Output> out = SearchRecords.run(new List<SearchRecords.Input>{ inp });
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(JSON.serialize(out[0].results));
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Object o : raw) {
            results.add((Map<String, Object>) o);
        }
        return results;
    }

    private static void assertThrows(String searchTerm, String objectApiName, String scenario) {
        SearchRecords.Input inp = new SearchRecords.Input();
        inp.searchTerm = searchTerm;
        inp.objectApiName = objectApiName;
        Boolean threw = false;
        try {
            SearchRecords.run(new List<SearchRecords.Input>{ inp });
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected exception for scenario: ' + scenario);
    }

    // ─── 1. Input validation ──────────────────────────────────────────────────────

    @isTest
    static void testInputValidation() {
        assertThrows(null,   AGENT_OBJECT,      'missing/null searchTerm');
        assertThrows('Acme', null,           'missing/null objectApiName');
        assertThrows('   ',  AGENT_OBJECT,      'blank searchTerm');
        assertThrows('Acme', '  ',           'blank objectApiName');
        assertThrows('Acme', 'FakeObject__c','unknown object');
    }

    // ─── 1b. Objects whose name field isn't "Name" ────────────────────────────────
    // Only standard objects have a name field other than Name, so this checks the
    // lookup and the SOSL built from it without inserting a Case record.

    @isTest
    static void testObjectWithNonNameField() {
        Assert.areEqual('CaseNumber', ApexAgentUtils.getNameField(ApexAgentUtils.getDescribe('Case')),
            'Case should resolve CaseNumber as its name field');

        Test.setFixedSearchResults(new List<Id>());
        Test.startTest();
        List<Map<String, Object>> results = search('00001001', 'Case');
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'A SOSL query returning CaseNumber should run and return no rows');
    }

    // ─── 1c. Scores are not diluted; suffix-only terms don't inflate scores ───────

    @isTest
    static void testWordOverlapAndSuffixOnlyTerms() {
        List<ApexAgent_Agent__c> accts = newAgents(new List<String>{ 'Accenture', 'Accenture Consulting' });
        insert accts;
        Test.setFixedSearchResults(new List<Id>{ accts[0].Id, accts[1].Id });
        Test.startTest();
        List<Map<String, Object>> exact = search('Accenture', AGENT_OBJECT);
        Test.stopTest();
        // 100 exact + 60 starts-with + 50 ends-with + 30 contains + 40 word overlap + 20 similarity
        Assert.areEqual('Accenture', exact[0].get('name'), 'Exact match first');
        Assert.areEqual(300.0, (Double) exact[0].get('score'), 'A perfect single-word match must earn the full word-overlap points');

        // A term made only of company suffixes must not turn every record into an exact/starts-with hit
        List<ApexAgent_Agent__c> suffixAccts = newAgents(new List<String>{ 'LLC', 'Suffix Test Group', 'Zeta Holdings' });
        insert suffixAccts;
        Test.setFixedSearchResults(new List<Id>{ suffixAccts[0].Id, suffixAccts[1].Id, suffixAccts[2].Id });
        List<Map<String, Object>> suffix = search('Group', AGENT_OBJECT);
        Assert.areEqual('Suffix Test Group', suffix[0].get('name'), 'The record containing the word ranks first');
        for (Integer i = 1; i < suffix.size(); i++) {
            Assert.isTrue((Double) suffix[i].get('score') < 30,
                'Unrelated record must not get the flat suffix-only bonus — ' + suffix[i]);
        }
    }

    // ─── 2. Scoring: exact > starts-with > contains ───────────────────────────────

    @isTest
    static void testScoringExactBeforePartialBeforeContains() {
        List<ApexAgent_Agent__c> accts = [SELECT Id, Name FROM ApexAgent_Agent__c WHERE Name IN ('Acme Inc', 'Acme Corp', 'My Acme Partner')];
        Map<String, Id> nameToId = new Map<String, Id>();
        for (ApexAgent_Agent__c a : accts) { nameToId.put(a.Name, a.Id); }

        Test.setFixedSearchResults(new List<Id>{
            nameToId.get('Acme Inc'),
            nameToId.get('Acme Corp'),
            nameToId.get('My Acme Partner')
        });

        Test.startTest();
        List<Map<String, Object>> results = search('Acme Inc', AGENT_OBJECT);
        Test.stopTest();

        Assert.isFalse(results.isEmpty(), 'Expected results');
        Assert.areEqual('Acme Inc', results[0].get('name'), 'Exact match must rank first');

        Double score0 = (Double) results[0].get('score');
        Double score1 = (Double) results[1].get('score');
        Double score2 = (Double) results[2].get('score');
        Assert.isTrue(score0 >= score1, 'Exact must outscore starts-with');
        Assert.isTrue(score1 >= score2, 'Starts-with must outscore contains');
        Assert.isTrue(score0 >= 100, 'Exact match must include 100-pt bonus');
    }

    // ─── 3. Sort order, score positivity, max-25 cap ─────────────────────────────

    @isTest
    static void testSortOrderAndScoreDescending() {
        List<String> bulkNames = new List<String>();
        for (Integer i = 1; i <= 30; i++) {
            bulkNames.add('Test Company ' + i);
        }
        insert newAgents(bulkNames);

        List<Id> bulkIds = new List<Id>();
        for (ApexAgent_Agent__c a : [SELECT Id FROM ApexAgent_Agent__c WHERE Name LIKE 'Test Company %']) {
            bulkIds.add(a.Id);
        }
        Test.setFixedSearchResults(bulkIds);

        Test.startTest();
        List<Map<String, Object>> results = search('Test Company', AGENT_OBJECT);
        Test.stopTest();

        Assert.isTrue(results.size() <= 25, 'Must be capped at 25, got: ' + results.size());
        for (Map<String, Object> r : results) {
            Assert.isTrue(((Double) r.get('score')) > 0, 'All scores must be positive');
        }
        for (Integer i = 1; i < results.size(); i++) {
            Double prev = (Double) results[i - 1].get('score');
            Double curr = (Double) results[i].get('score');
            Assert.isTrue(prev >= curr, 'Results must be descending at index ' + i);
        }
    }

    // ─── 4. Person name variants ──────────────────────────────────────────────────

    @isTest
    static void testPersonNameVariants() {
        ApexAgent_Agent__c johnSmith = agentNamed('John Smith');
        ApexAgent_Agent__c johnAdams = agentNamed('John Adams');
        ApexAgent_Agent__c janeDoe = agentNamed('Jane Doe');

        // First name only — both Johns
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id, johnAdams.Id });
        Test.startTest();
        List<Map<String, Object>> byFirst = search('John', AGENT_OBJECT);
        Test.stopTest();
        Assert.areEqual(2, byFirst.size(), 'Both Johns must be returned');
        for (Map<String, Object> r : byFirst) {
            Assert.isTrue(((Double) r.get('score')) > 0, 'First-name score must be positive');
        }

        // Last name only
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> byLast = search('Smith', AGENT_OBJECT);
        Assert.isFalse(byLast.isEmpty(), 'Last-name search must return Smith');

        // Full name — John Smith #1
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id, janeDoe.Id });
        List<Map<String, Object>> byFull = search('John Smith', AGENT_OBJECT);
        Assert.areEqual('John Smith', byFull[0].get('name'), 'Full name must rank first');

        // Transposed: "Smith John" still returns John Smith
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> byTransposed = search('Smith John', AGENT_OBJECT);
        Assert.isFalse(byTransposed.isEmpty(), 'Transposed name must return results');
        Assert.isTrue(((Double) byTransposed[0].get('score')) > 0, 'Transposed name must score > 0');

        // Typo: "Jon Smith" — Levenshtein handles it
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> byTypo = search('Jon Smith', AGENT_OBJECT);
        Assert.isFalse(byTypo.isEmpty(), 'Typo must return results via Levenshtein');
        Assert.isTrue(((Double) byTypo[0].get('score')) > 0, 'Typo must score > 0');

        // Full name scores >= first-name-only for the same record
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> firstOnly = search('John', AGENT_OBJECT);
        Assert.isTrue(((Double) byFull[0].get('score')) >= ((Double) firstOnly[0].get('score')),
            'Full name must score >= first-name-only');
    }

    // ─── 5. Company name variants ─────────────────────────────────────────────────

    @isTest
    static void testCompanyNameVariants() {
        ApexAgent_Agent__c acmeInc = agentNamed('Acme Inc');
        ApexAgent_Agent__c acmeCorp = agentNamed('Acme Corp');
        ApexAgent_Agent__c techNova = agentNamed('TechNova Group Holdings');
        ApexAgent_Agent__c globalAcc = agentNamed('Global Solutions LLC');

        // Clean name (no suffix): both Acme accounts returned
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id, acmeCorp.Id });
        Test.startTest();
        List<Map<String, Object>> byClean = search('Acme', AGENT_OBJECT);
        Test.stopTest();
        Set<String> returnedNames = new Set<String>();
        for (Map<String, Object> r : byClean) { returnedNames.add((String) r.get('name')); }
        Assert.isTrue(returnedNames.contains('Acme Inc'),  'Acme Inc must be in results');
        Assert.isTrue(returnedNames.contains('Acme Corp'), 'Acme Corp must be in results');

        // Exact with suffix: "Acme Inc" is #1 with high score
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id, acmeCorp.Id });
        List<Map<String, Object>> byFullCompany = search('Acme Inc', AGENT_OBJECT);
        Assert.areEqual('Acme Inc', byFullCompany[0].get('name'), 'Acme Inc must rank first');
        Assert.isTrue(((Double) byFullCompany[0].get('score')) >= 100, 'Exact company must score >= 100');

        // Multi-word found by brand word
        Test.setFixedSearchResults(new List<Id>{ techNova.Id });
        List<Map<String, Object>> byBrand = search('TechNova', AGENT_OBJECT);
        Assert.isFalse(byBrand.isEmpty(), 'TechNova must be found by brand name');

        // Suffix-only "LLC" should score much lower than an exact match
        Test.setFixedSearchResults(new List<Id>{ globalAcc.Id });
        List<Map<String, Object>> bySuffix = search('LLC', AGENT_OBJECT);
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        List<Map<String, Object>> byExact = search('Acme Inc', AGENT_OBJECT);
        if (!bySuffix.isEmpty()) {
            Assert.isTrue(
                ((Double) byExact[0].get('score')) > ((Double) bySuffix[0].get('score')),
                'Exact name must outscore suffix-only search'
            );
        }
    }

    // ─── 6. Diverse search terms and edge cases ───────────────────────────────────
    // Covers: acronyms, case-insensitivity, numeric names, CamelCase brands,
    // hyphenated names, fuzzy/typo, apostrophes, partial word, three-part name,
    // initials search

    @isTest
    static void testDiverseSearchTermsAndEdgeCases() {
        ApexAgent_Agent__c ibmAcc = agentNamed('IBM Global Services');
        ApexAgent_Agent__c acc3m = agentNamed('3M Corporation');
        ApexAgent_Agent__c smithJonesAcc = agentNamed('Smith-Jones Consulting');
        ApexAgent_Agent__c qbAcc = agentNamed('QuickBooks Online');
        ApexAgent_Agent__c sfAcc = agentNamed('Salesforce Inc');
        ApexAgent_Agent__c globalAcc = agentNamed('Global Solutions LLC');
        ApexAgent_Agent__c rajContact = agentNamed('Raj Kumar');
        ApexAgent_Agent__c maryContact = agentNamed('Mary O\'Brien');
        ApexAgent_Agent__c jpContact = agentNamed('Jean-Pierre Dupont');
        ApexAgent_Agent__c johnSmith = agentNamed('John Smith');

        Test.startTest();

        // ── Acronym: "IBM" → IBM Global Services ──────────────────────────────
        Test.setFixedSearchResults(new List<Id>{ ibmAcc.Id });
        List<Map<String, Object>> ibmResults = search('IBM', AGENT_OBJECT);
        Assert.isFalse(ibmResults.isEmpty(), 'IBM must return results');
        Assert.isTrue(((Double) ibmResults[0].get('score')) >= 100,
            'IBM acronym should score >= 100 (starts-with + contains + word match)');

        // ── Case insensitivity: "ibm" == "IBM" score ───────────────────────────
        Test.setFixedSearchResults(new List<Id>{ ibmAcc.Id });
        List<Map<String, Object>> ibmLower = search('ibm', AGENT_OBJECT);
        Assert.areEqual(
            (Double) ibmResults[0].get('score'),
            (Double) ibmLower[0].get('score'),
            'Search must be case-insensitive: IBM and ibm should produce equal scores'
        );

        // ── Numeric company name: "3M" → 3M Corporation ───────────────────────
        Test.setFixedSearchResults(new List<Id>{ acc3m.Id });
        List<Map<String, Object>> results3m = search('3M', AGENT_OBJECT);
        Assert.isFalse(results3m.isEmpty(), '3M must return results');
        Assert.isTrue(((Double) results3m[0].get('score')) > 0, '3M must score > 0');

        // ── CamelCase brand: "quickbooks" → QuickBooks Online ─────────────────
        Test.setFixedSearchResults(new List<Id>{ qbAcc.Id });
        List<Map<String, Object>> qbResults = search('quickbooks', AGENT_OBJECT);
        Assert.isFalse(qbResults.isEmpty(), 'quickbooks must find QuickBooks Online');
        Assert.isTrue(((Double) qbResults[0].get('score')) >= 100,
            'quickbooks should score >= 100 (starts-with + contains + word match)');

        // ── Hyphenated company: "Smith Jones" → Smith-Jones Consulting ──────────
        Test.setFixedSearchResults(new List<Id>{ smithJonesAcc.Id });
        List<Map<String, Object>> hyphenResults = search('Smith Jones', AGENT_OBJECT);
        Assert.isFalse(hyphenResults.isEmpty(), 'Smith Jones must find Smith-Jones Consulting');
        Assert.isTrue(((Double) hyphenResults[0].get('score')) > 0, 'Hyphenated company must score > 0');

        // ── Fuzzy / typo: "saleforce" → Salesforce Inc (1 missing char) ────────
        Test.setFixedSearchResults(new List<Id>{ sfAcc.Id });
        List<Map<String, Object>> fuzzyResults = search('saleforce', AGENT_OBJECT);
        Assert.isFalse(fuzzyResults.isEmpty(), 'Typo "saleforce" must return Salesforce via Levenshtein');
        Assert.isTrue(((Double) fuzzyResults[0].get('score')) > 0, 'Fuzzy match must score > 0');

        // ── Apostrophe in name: "OBrien" → Mary O'Brien ───────────────────────
        Test.setFixedSearchResults(new List<Id>{ maryContact.Id });
        List<Map<String, Object>> obrienResults = search('OBrien', AGENT_OBJECT);
        Assert.isFalse(obrienResults.isEmpty(), 'OBrien must return Mary O\'Brien');
        Assert.isTrue(((Double) obrienResults[0].get('score')) > 0, 'Apostrophe name must score > 0');

        // ── Hyphenated first name: "Jean Pierre" → Jean-Pierre Dupont ──────────
        Test.setFixedSearchResults(new List<Id>{ jpContact.Id });
        List<Map<String, Object>> jpResults = search('Jean-Pierre Dupont', AGENT_OBJECT);
        Assert.isFalse(jpResults.isEmpty(), 'Jean-Pierre Dupont must return results');
        Assert.isTrue(((Double) jpResults[0].get('score')) > 0, 'Hyphenated first name must score > 0');

        // ── Three-token person: "Raj Kumar" (exact) ───────────────────────────
        Test.setFixedSearchResults(new List<Id>{ rajContact.Id });
        List<Map<String, Object>> rajResults = search('Raj Kumar', AGENT_OBJECT);
        Assert.isFalse(rajResults.isEmpty(), 'Raj Kumar must return results');
        Assert.areEqual('Raj Kumar', rajResults[0].get('name'), 'Raj Kumar must be top result');
        Assert.isTrue(((Double) rajResults[0].get('score')) >= 100, 'Exact person name must score >= 100');

        // ── Partial company word: "solutions" → Global Solutions LLC ──────────
        Test.setFixedSearchResults(new List<Id>{ globalAcc.Id });
        List<Map<String, Object>> partialWordResults = search('solutions', AGENT_OBJECT);
        Assert.isFalse(partialWordResults.isEmpty(), '"solutions" must find Global Solutions LLC');
        Assert.isTrue(((Double) partialWordResults[0].get('score')) >= 50,
            '"solutions" word match + contains should score >= 50');

        // ── Initials: "J Smith" → John Smith ──────────────────────────────────
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> initialsResults = search('J Smith', AGENT_OBJECT);
        Assert.isFalse(initialsResults.isEmpty(), '"J Smith" initials must return John Smith');
        Assert.isTrue(((Double) initialsResults[0].get('score')) > 0, 'Initials must score > 0');

        // ── Mixed case term: "ACME INC" same score as "Acme Inc" ─────────────
        ApexAgent_Agent__c acmeInc = agentNamed('Acme Inc');
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        List<Map<String, Object>> upperResults = search('ACME INC', AGENT_OBJECT);
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        List<Map<String, Object>> mixedResults = search('Acme Inc', AGENT_OBJECT);
        Assert.areEqual(
            (Double) upperResults[0].get('score'),
            (Double) mixedResults[0].get('score'),
            'ACME INC and Acme Inc must produce identical scores (case-insensitive)'
        );

        Test.stopTest();
    }

    // ─── 7. Result structure + empty results ─────────────────────────────────────

    @isTest
    static void testResultStructure() {
        ApexAgent_Agent__c acmeInc = agentNamed('Acme Inc');

        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        Test.startTest();
        List<Map<String, Object>> results = search('Acme', AGENT_OBJECT);
        Test.stopTest();

        Assert.isFalse(results.isEmpty(), 'Expected at least one result');
        Map<String, Object> first = results[0];
        Assert.isTrue(first.containsKey('id'),    'Result must contain id');
        Assert.isTrue(first.containsKey('name'),  'Result must contain name');
        Assert.isTrue(first.containsKey('score'), 'Result must contain score');

        String recordId = String.valueOf(first.get('id'));
        Assert.isTrue(recordId.length() == 15 || recordId.length() == 18, 'Id must be 15 or 18 chars');
        Assert.isTrue(recordId.startsWith(ApexAgent_Agent__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix()),
            'Id must carry the searched object\'s key prefix');

        // Empty SOSL → empty list, no exception
        Test.setFixedSearchResults(new List<Id>());
        List<Map<String, Object>> emptyResults = search('Acme', AGENT_OBJECT);
        Assert.areEqual(0, emptyResults.size(), 'Empty SOSL must produce empty list');
    }

    // ─── 8. SOSL escaping ──────────────────────────────────────────────────────────
    // escapeSosl must escape every reserved SOSL character it advertises escaping —
    // previously { } ( ) * ? were silently left unescaped, which could break out of
    // the surrounding FIND {...} block or be misread as unintended wildcards.

    @isTest
    static void testEscapeSoslEscapesAllReservedCharacters() {
        Assert.areEqual('a\\{b\\}c',  SearchRecords.escapeSosl('a{b}c'),  'Curly braces must be escaped');
        Assert.areEqual('a\\(b\\)c',  SearchRecords.escapeSosl('a(b)c'),  'Parentheses must be escaped');
        Assert.areEqual('a\\*b',      SearchRecords.escapeSosl('a*b'),    'Asterisk must be escaped');
        Assert.areEqual('a\\?b',      SearchRecords.escapeSosl('a?b'),    'Question mark must be escaped');
        Assert.areEqual('a\\[b\\]c',  SearchRecords.escapeSosl('a[b]c'),  'Square brackets must be escaped');
        Assert.areEqual('a\\\\b',     SearchRecords.escapeSosl('a\\b'),   'Backslash must be escaped');
        Assert.areEqual('a\\"b',      SearchRecords.escapeSosl('a"b'),    'Double quote must be escaped');

        // A term combining several reserved characters, including one that would
        // otherwise close the FIND {...} block early
        Assert.areEqual(
            '\\{escape\\}\\*me\\?',
            SearchRecords.escapeSosl('{escape}*me?'),
            'Combined reserved characters must all be escaped'
        );

        // End-to-end: a search term full of reserved characters must not throw when
        // building/executing the SOSL clause (Test.setFixedSearchResults bypasses the
        // actual query engine, so this exercises clause construction, not the escaped
        // query string itself)
        Test.setFixedSearchResults(new List<Id>());
        Test.startTest();
        List<Map<String, Object>> results = search('{Acme} (Inc)*?', AGENT_OBJECT);
        Test.stopTest();
        Assert.isNotNull(results, 'Search with reserved characters must not throw');
    }

    // ─── 9. ApexAgentUtils ───────────────────────────────────────────────────────

    @isTest
    static void testApexAgentUtils() {
        Test.startTest();

        Schema.DescribeSObjectResult describeResult = ApexAgentUtils.getDescribe(AGENT_OBJECT);
        Assert.isNotNull(describeResult, 'getDescribe must return non-null for ApexAgent_Agent__c');
        Assert.areEqual(AGENT_OBJECT, describeResult.getName(), 'Describe name must be ApexAgent_Agent__c');

        Boolean threw = false;
        try {
            ApexAgentUtils.getDescribe('FakeObject__c');
        } catch (IllegalArgumentException e) {
            threw = true;
            Assert.isTrue(e.getMessage().containsIgnoreCase('Unknown'), 'Error must mention "Unknown"');
        }
        Assert.isTrue(threw, 'Unknown object must throw IllegalArgumentException');

        Test.stopTest();
    }
}
