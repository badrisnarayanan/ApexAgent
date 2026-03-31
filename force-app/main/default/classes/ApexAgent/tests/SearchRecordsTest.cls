@isTest
private class SearchRecordsTest {

    // ─── Test data ────────────────────────────────────────────────────────────────

    @testSetup
    static void setup() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Acme Inc'),
            new Account(Name = 'Acme Corp'),
            new Account(Name = 'Acme Technologies'),
            new Account(Name = 'Global Solutions LLC'),
            new Account(Name = 'TechNova Group Holdings'),
            new Account(Name = 'My Acme Partner'),
            // Diverse formats for edge-case testing
            new Account(Name = 'IBM Global Services'),
            new Account(Name = '3M Corporation'),
            new Account(Name = 'Smith-Jones Consulting'),
            new Account(Name = 'QuickBooks Online'),
            new Account(Name = 'Salesforce Inc')
        };
        insert accounts;

        Account acmeInc = [SELECT Id FROM Account WHERE Name = 'Acme Inc' LIMIT 1];
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'John',       LastName = 'Smith',    AccountId = acmeInc.Id),
            new Contact(FirstName = 'Jane',       LastName = 'Doe',      AccountId = acmeInc.Id),
            new Contact(FirstName = 'Alice',      LastName = 'Johnson',  AccountId = acmeInc.Id),
            new Contact(FirstName = 'John',       LastName = 'Adams',    AccountId = acmeInc.Id),
            new Contact(FirstName = 'Smith',      LastName = 'Williams', AccountId = acmeInc.Id),
            // Diverse name formats
            new Contact(FirstName = 'Raj',        LastName = 'Kumar',    AccountId = acmeInc.Id),
            new Contact(FirstName = 'Mary',       LastName = 'O\'Brien', AccountId = acmeInc.Id),
            new Contact(FirstName = 'Jean-Pierre',LastName = 'Dupont',   AccountId = acmeInc.Id)
        };
        insert contacts;
    }

    // ─── Helper ───────────────────────────────────────────────────────────────────

    private static void assertThrows(SearchRecords tool, Map<String, Object> input, String scenario) {
        Boolean threw = false;
        try {
            tool.execute(input);
        } catch (IllegalArgumentException e) {
            threw = true;
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected exception for scenario: ' + scenario);
    }

    // ─── 1. Input validation ──────────────────────────────────────────────────────

    @isTest
    static void testInputValidation() {
        SearchRecords tool = new SearchRecords();

        assertThrows(tool, null,                                                                         'null input map');
        assertThrows(tool, new Map<String, Object>{ 'objectApiName' => 'Account' },                     'missing searchTerm');
        assertThrows(tool, new Map<String, Object>{ 'searchTerm' => 'Acme' },                           'missing objectApiName');
        assertThrows(tool, new Map<String, Object>{ 'searchTerm' => null,  'objectApiName' => 'Account' }, 'null searchTerm');
        assertThrows(tool, new Map<String, Object>{ 'searchTerm' => '   ', 'objectApiName' => 'Account' }, 'blank searchTerm');
        assertThrows(tool, new Map<String, Object>{ 'searchTerm' => 'Acme', 'objectApiName' => null },  'null objectApiName');
        assertThrows(tool, new Map<String, Object>{ 'searchTerm' => 'Acme', 'objectApiName' => '  ' }, 'blank objectApiName');
        assertThrows(tool, new Map<String, Object>{ 'searchTerm' => 'Acme', 'objectApiName' => 'FakeObject__c' }, 'unknown object');
    }

    // ─── 2. Scoring: exact > starts-with > contains ───────────────────────────────

    @isTest
    static void testScoringExactBeforePartialBeforeContains() {
        List<Account> accts = [SELECT Id, Name FROM Account WHERE Name IN ('Acme Inc', 'Acme Corp', 'My Acme Partner')];
        Map<String, Id> nameToId = new Map<String, Id>();
        for (Account a : accts) { nameToId.put(a.Name, a.Id); }

        Test.setFixedSearchResults(new List<Id>{
            nameToId.get('Acme Inc'),
            nameToId.get('Acme Corp'),
            nameToId.get('My Acme Partner')
        });

        Test.startTest();
        SearchRecords tool = new SearchRecords();
        List<Map<String, Object>> results = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Acme Inc', 'objectApiName' => 'Account' }
        );
        Test.stopTest();

        Assert.isFalse(results.isEmpty(), 'Expected results');
        Assert.areEqual('Acme Inc', results[0].get('Name'), 'Exact match must rank first');

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
        List<Account> bulkAccounts = new List<Account>();
        for (Integer i = 1; i <= 30; i++) {
            bulkAccounts.add(new Account(Name = 'Test Company ' + i));
        }
        insert bulkAccounts;

        List<Id> bulkIds = new List<Id>();
        for (Account a : [SELECT Id FROM Account WHERE Name LIKE 'Test Company %']) {
            bulkIds.add(a.Id);
        }
        Test.setFixedSearchResults(bulkIds);

        Test.startTest();
        SearchRecords tool = new SearchRecords();
        List<Map<String, Object>> results = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Test Company', 'objectApiName' => 'Account' }
        );
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
        Contact johnSmith = [SELECT Id FROM Contact WHERE FirstName = 'John' AND LastName = 'Smith' LIMIT 1];
        Contact johnAdams = [SELECT Id FROM Contact WHERE FirstName = 'John' AND LastName = 'Adams' LIMIT 1];
        Contact janeDoe   = [SELECT Id FROM Contact WHERE FirstName = 'Jane' AND LastName = 'Doe'   LIMIT 1];

        SearchRecords tool = new SearchRecords();

        // First name only — both Johns
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id, johnAdams.Id });
        Test.startTest();
        List<Map<String, Object>> byFirst = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'John', 'objectApiName' => 'Contact' }
        );
        Test.stopTest();
        Assert.areEqual(2, byFirst.size(), 'Both Johns must be returned');
        for (Map<String, Object> r : byFirst) {
            Assert.isTrue(((Double) r.get('score')) > 0, 'First-name score must be positive');
        }

        // Last name only
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> byLast = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Smith', 'objectApiName' => 'Contact' }
        );
        Assert.isFalse(byLast.isEmpty(), 'Last-name search must return Smith');

        // Full name — John Smith #1
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id, janeDoe.Id });
        List<Map<String, Object>> byFull = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'John Smith', 'objectApiName' => 'Contact' }
        );
        Assert.areEqual('John Smith', byFull[0].get('Name'), 'Full name must rank first');

        // Transposed: "Smith John" still returns John Smith
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> byTransposed = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Smith John', 'objectApiName' => 'Contact' }
        );
        Assert.isFalse(byTransposed.isEmpty(), 'Transposed name must return results');
        Assert.isTrue(((Double) byTransposed[0].get('score')) > 0, 'Transposed name must score > 0');

        // Typo: "Jon Smith" — Levenshtein handles it
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> byTypo = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Jon Smith', 'objectApiName' => 'Contact' }
        );
        Assert.isFalse(byTypo.isEmpty(), 'Typo must return results via Levenshtein');
        Assert.isTrue(((Double) byTypo[0].get('score')) > 0, 'Typo must score > 0');

        // Full name scores >= first-name-only for the same record
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> firstOnly = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'John', 'objectApiName' => 'Contact' }
        );
        Assert.isTrue(((Double) byFull[0].get('score')) >= ((Double) firstOnly[0].get('score')),
            'Full name must score >= first-name-only');
    }

    // ─── 5. Company name variants ─────────────────────────────────────────────────

    @isTest
    static void testCompanyNameVariants() {
        Account acmeInc  = [SELECT Id FROM Account WHERE Name = 'Acme Inc'  LIMIT 1];
        Account acmeCorp = [SELECT Id FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        Account techNova = [SELECT Id FROM Account WHERE Name = 'TechNova Group Holdings' LIMIT 1];
        Account globalAcc = [SELECT Id FROM Account WHERE Name = 'Global Solutions LLC' LIMIT 1];

        SearchRecords tool = new SearchRecords();

        // Clean name (no suffix): both Acme accounts returned
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id, acmeCorp.Id });
        Test.startTest();
        List<Map<String, Object>> byClean = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Acme', 'objectApiName' => 'Account' }
        );
        Test.stopTest();
        Set<String> returnedNames = new Set<String>();
        for (Map<String, Object> r : byClean) { returnedNames.add((String) r.get('Name')); }
        Assert.isTrue(returnedNames.contains('Acme Inc'),  'Acme Inc must be in results');
        Assert.isTrue(returnedNames.contains('Acme Corp'), 'Acme Corp must be in results');

        // Exact with suffix: "Acme Inc" is #1 with high score
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id, acmeCorp.Id });
        List<Map<String, Object>> byFullCompany = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Acme Inc', 'objectApiName' => 'Account' }
        );
        Assert.areEqual('Acme Inc', byFullCompany[0].get('Name'), 'Acme Inc must rank first');
        Assert.isTrue(((Double) byFullCompany[0].get('score')) >= 100, 'Exact company must score >= 100');

        // Multi-word found by brand word
        Test.setFixedSearchResults(new List<Id>{ techNova.Id });
        List<Map<String, Object>> byBrand = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'TechNova', 'objectApiName' => 'Account' }
        );
        Assert.isFalse(byBrand.isEmpty(), 'TechNova must be found by brand name');

        // Suffix-only "LLC" should score much lower than an exact match
        Test.setFixedSearchResults(new List<Id>{ globalAcc.Id });
        List<Map<String, Object>> bySuffix = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'LLC', 'objectApiName' => 'Account' }
        );
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        List<Map<String, Object>> byExact = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Acme Inc', 'objectApiName' => 'Account' }
        );
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
        Account ibmAcc       = [SELECT Id FROM Account WHERE Name = 'IBM Global Services'    LIMIT 1];
        Account acc3m        = [SELECT Id FROM Account WHERE Name = '3M Corporation'         LIMIT 1];
        Account smithJonesAcc= [SELECT Id FROM Account WHERE Name = 'Smith-Jones Consulting' LIMIT 1];
        Account qbAcc        = [SELECT Id FROM Account WHERE Name = 'QuickBooks Online'       LIMIT 1];
        Account sfAcc        = [SELECT Id FROM Account WHERE Name = 'Salesforce Inc'         LIMIT 1];
        Account globalAcc    = [SELECT Id FROM Account WHERE Name = 'Global Solutions LLC'   LIMIT 1];
        Contact rajContact   = [SELECT Id FROM Contact WHERE FirstName = 'Raj' AND LastName = 'Kumar'   LIMIT 1];
        Contact maryContact  = [SELECT Id FROM Contact WHERE FirstName = 'Mary' AND LastName = 'O\'Brien' LIMIT 1];
        Contact jpContact    = [SELECT Id FROM Contact WHERE FirstName = 'Jean-Pierre' AND LastName = 'Dupont' LIMIT 1];
        Contact johnSmith    = [SELECT Id FROM Contact WHERE FirstName = 'John' AND LastName = 'Smith'  LIMIT 1];

        SearchRecords tool = new SearchRecords();
        Test.startTest();

        // ── Acronym: "IBM" → IBM Global Services ──────────────────────────────
        // Expects: starts-with(+60) + contains(+30) + word-overlap(+40) = 130+
        Test.setFixedSearchResults(new List<Id>{ ibmAcc.Id });
        List<Map<String, Object>> ibmResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'IBM', 'objectApiName' => 'Account' }
        );
        Assert.isFalse(ibmResults.isEmpty(), 'IBM must return results');
        Assert.isTrue(((Double) ibmResults[0].get('score')) >= 100,
            'IBM acronym should score >= 100 (starts-with + contains + word match)');

        // ── Case insensitivity: "ibm" == "IBM" score ───────────────────────────
        Test.setFixedSearchResults(new List<Id>{ ibmAcc.Id });
        List<Map<String, Object>> ibmLower = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'ibm', 'objectApiName' => 'Account' }
        );
        Assert.areEqual(
            (Double) ibmResults[0].get('score'),
            (Double) ibmLower[0].get('score'),
            'Search must be case-insensitive: IBM and ibm should produce equal scores'
        );

        // ── Numeric company name: "3M" → 3M Corporation ───────────────────────
        Test.setFixedSearchResults(new List<Id>{ acc3m.Id });
        List<Map<String, Object>> results3m = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => '3M', 'objectApiName' => 'Account' }
        );
        Assert.isFalse(results3m.isEmpty(), '3M must return results');
        Assert.isTrue(((Double) results3m[0].get('score')) > 0, '3M must score > 0');

        // ── CamelCase brand: "quickbooks" → QuickBooks Online ─────────────────
        // Contains check fires: "quickbooks online".contains("quickbooks") = true (+60 +30 +40)
        Test.setFixedSearchResults(new List<Id>{ qbAcc.Id });
        List<Map<String, Object>> qbResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'quickbooks', 'objectApiName' => 'Account' }
        );
        Assert.isFalse(qbResults.isEmpty(), 'quickbooks must find QuickBooks Online');
        Assert.isTrue(((Double) qbResults[0].get('score')) >= 100,
            'quickbooks should score >= 100 (starts-with + contains + word match)');

        // ── Hyphenated company: "Smith Jones" → Smith-Jones Consulting ──────────
        // Contains fires on individual words, Levenshtein provides similarity
        Test.setFixedSearchResults(new List<Id>{ smithJonesAcc.Id });
        List<Map<String, Object>> hyphenResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Smith Jones', 'objectApiName' => 'Account' }
        );
        Assert.isFalse(hyphenResults.isEmpty(), 'Smith Jones must find Smith-Jones Consulting');
        Assert.isTrue(((Double) hyphenResults[0].get('score')) > 0, 'Hyphenated company must score > 0');

        // ── Fuzzy / typo: "saleforce" → Salesforce Inc (1 missing char) ────────
        // Only Levenshtein fires; expect low but positive score
        Test.setFixedSearchResults(new List<Id>{ sfAcc.Id });
        List<Map<String, Object>> fuzzyResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'saleforce', 'objectApiName' => 'Account' }
        );
        Assert.isFalse(fuzzyResults.isEmpty(), 'Typo "saleforce" must return Salesforce via Levenshtein');
        Assert.isTrue(((Double) fuzzyResults[0].get('score')) > 0, 'Fuzzy match must score > 0');

        // ── Apostrophe in name: "OBrien" → Mary O'Brien ───────────────────────
        // Apostrophe prevents exact contains; Levenshtein provides a positive score
        Test.setFixedSearchResults(new List<Id>{ maryContact.Id });
        List<Map<String, Object>> obrienResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'OBrien', 'objectApiName' => 'Contact' }
        );
        Assert.isFalse(obrienResults.isEmpty(), 'OBrien must return Mary O\'Brien');
        Assert.isTrue(((Double) obrienResults[0].get('score')) > 0, 'Apostrophe name must score > 0');

        // ── Hyphenated first name: "Jean Pierre" → Jean-Pierre Dupont ──────────
        Test.setFixedSearchResults(new List<Id>{ jpContact.Id });
        List<Map<String, Object>> jpResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Jean-Pierre Dupont', 'objectApiName' => 'Contact' }
        );
        Assert.isFalse(jpResults.isEmpty(), 'Jean-Pierre Dupont must return results');
        Assert.isTrue(((Double) jpResults[0].get('score')) > 0, 'Hyphenated first name must score > 0');

        // ── Three-token person: "Raj Kumar" (exact) ───────────────────────────
        // Exact match: score >= 100
        Test.setFixedSearchResults(new List<Id>{ rajContact.Id });
        List<Map<String, Object>> rajResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Raj Kumar', 'objectApiName' => 'Contact' }
        );
        Assert.isFalse(rajResults.isEmpty(), 'Raj Kumar must return results');
        Assert.areEqual('Raj Kumar', rajResults[0].get('Name'), 'Raj Kumar must be top result');
        Assert.isTrue(((Double) rajResults[0].get('score')) >= 100, 'Exact person name must score >= 100');

        // ── Partial company word: "solutions" → Global Solutions LLC ──────────
        // Word overlap fires (solutions in name word set) + contains → expect score >= 50
        Test.setFixedSearchResults(new List<Id>{ globalAcc.Id });
        List<Map<String, Object>> partialWordResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'solutions', 'objectApiName' => 'Account' }
        );
        Assert.isFalse(partialWordResults.isEmpty(), '"solutions" must find Global Solutions LLC');
        Assert.isTrue(((Double) partialWordResults[0].get('score')) >= 50,
            '"solutions" word match + contains should score >= 50');

        // ── Initials: "J Smith" → John Smith ──────────────────────────────────
        Test.setFixedSearchResults(new List<Id>{ johnSmith.Id });
        List<Map<String, Object>> initialsResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'J Smith', 'objectApiName' => 'Contact' }
        );
        Assert.isFalse(initialsResults.isEmpty(), '"J Smith" initials must return John Smith');
        Assert.isTrue(((Double) initialsResults[0].get('score')) > 0, 'Initials must score > 0');

        // ── Mixed case term: "ACME INC" same score as "Acme Inc" ─────────────
        Account acmeInc = [SELECT Id FROM Account WHERE Name = 'Acme Inc' LIMIT 1];
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        List<Map<String, Object>> upperResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'ACME INC', 'objectApiName' => 'Account' }
        );
        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        List<Map<String, Object>> mixedResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Acme Inc', 'objectApiName' => 'Account' }
        );
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
        Account acmeInc = [SELECT Id FROM Account WHERE Name = 'Acme Inc' LIMIT 1];
        SearchRecords tool = new SearchRecords();

        Test.setFixedSearchResults(new List<Id>{ acmeInc.Id });
        Test.startTest();
        List<Map<String, Object>> results = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Acme', 'objectApiName' => 'Account' }
        );
        Test.stopTest();

        Assert.isFalse(results.isEmpty(), 'Expected at least one result');
        Map<String, Object> first = results[0];
        Assert.isTrue(first.containsKey('Id'),    'Result must contain Id');
        Assert.isTrue(first.containsKey('Name'),  'Result must contain Name');
        Assert.isTrue(first.containsKey('score'), 'Result must contain score');

        String recordId = String.valueOf(first.get('Id'));
        Assert.isTrue(recordId.length() == 15 || recordId.length() == 18, 'Id must be 15 or 18 chars');
        Assert.isTrue(recordId.startsWith('001'), 'Account Id must start with 001');

        // Empty SOSL → empty list, no exception
        Test.setFixedSearchResults(new List<Id>());
        List<Map<String, Object>> emptyResults = (List<Map<String, Object>>) tool.execute(
            new Map<String, Object>{ 'searchTerm' => 'Acme', 'objectApiName' => 'Account' }
        );
        Assert.areEqual(0, emptyResults.size(), 'Empty SOSL must produce empty list');
    }

    // ─── 8. ApexAgentUtils ───────────────────────────────────────────────────────

    @isTest
    static void testApexAgentUtils() {
        Test.startTest();

        Schema.DescribeSObjectResult describeResult = ApexAgentUtils.getDescribe('Account');
        Assert.isNotNull(describeResult, 'getDescribe must return non-null for Account');
        Assert.areEqual('Account', describeResult.getName(), 'Describe name must be Account');

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
