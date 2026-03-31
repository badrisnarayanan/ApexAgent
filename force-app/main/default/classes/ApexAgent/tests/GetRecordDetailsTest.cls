@IsTest
private class GetRecordDetailsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        GetRecordDetails tool = new GetRecordDetails();

        try {
            tool.execute(null);
            Assert.fail('Expected exception for null input');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('null'), 'Message should mention null');
        }

        try {
            tool.execute(new Map<String, Object>());
            Assert.fail('Expected exception for missing recordId key');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('recordId'), 'Message should mention recordId');
        }

        try {
            tool.execute(new Map<String, Object>{ 'recordId' => null });
            Assert.fail('Expected exception for null recordId');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('null'), 'Message should mention null');
        }

        try {
            tool.execute(new Map<String, Object>{ 'recordId' => '   ' });
            Assert.fail('Expected exception for blank recordId');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        try {
            tool.execute(new Map<String, Object>{ 'recordId' => 'not-a-valid-id' });
            Assert.fail('Expected exception for invalid ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('not a valid Salesforce ID'), 'Message should mention invalid ID');
        }
    }

    // ─── Happy path: standard object ─────────────────────────────────────────────

    @IsTest
    static void testHappyPath() {
        Account acc = new Account(Name = 'Test Account GetRecordDetails');
        insert acc;

        GetRecordDetails tool   = new GetRecordDetails();
        Map<String, Object> res = (Map<String, Object>) tool.execute(
            new Map<String, Object>{ 'recordId' => String.valueOf(acc.Id) }
        );

        // JSON.serialize produces flat fields + nested 'attributes' with type info
        Assert.areEqual('Test Account GetRecordDetails', res.get('Name'), 'Name should match');
        Assert.areEqual(String.valueOf(acc.Id), res.get('Id'), 'Id should match');
        Map<String, Object> attrs = (Map<String, Object>) res.get('attributes');
        Assert.areEqual('Account', attrs.get('type'), 'attributes.type should be Account');
    }

    // ─── Field filtering: long text areas excluded ────────────────────────────────

    @IsTest
    static void testFieldFiltering() {
        // Account.Description is a TEXTAREA with length 32000 — must be excluded
        Account acc = new Account(Name = 'Filter Test', Description = 'Some description text');
        insert acc;

        GetRecordDetails tool   = new GetRecordDetails();
        Map<String, Object> res = (Map<String, Object>) tool.execute(
            new Map<String, Object>{ 'recordId' => String.valueOf(acc.Id) }
        );

        Assert.isFalse(res.containsKey('Description'), 'Description (long textarea) should be excluded');
        Assert.isTrue(res.containsKey('Name'),          'Name (short text) should be included');
    }

    // ─── Record not found ────────────────────────────────────────────────────────

    @IsTest
    static void testRecordNotFound() {
        // Generate a syntactically valid but non-existent Account ID
        Account acc = new Account(Name = 'Temp');
        insert acc;
        Id ghostId = acc.Id;
        delete acc;

        GetRecordDetails tool   = new GetRecordDetails();
        Map<String, Object> res = (Map<String, Object>) tool.execute(
            new Map<String, Object>{ 'recordId' => String.valueOf(ghostId) }
        );

        Assert.areEqual(false, res.get('found'),   'found should be false');
        Assert.isNotNull(res.get('message'),        'message should be present');
    }

    // ─── Lookup enrichment: custom lookup field ───────────────────────────────────

    @IsTest
    static void testLookupEnrichment() {
        // ApexAgent_LLM__c has a Name field; ApexAgent_Agent__c has LLM__c (custom lookup)
        // LLM__c doesn't end with 'Id' so getRelationshipName() = 'LLM__r' gets enriched
        ApexAgent_LLM__c llm = new ApexAgent_LLM__c(
            Name              = 'Test LLM',
            Model_API_Name__c = 'test-model-1',
            Family__c         = 'Anthropic',
            Named_Credential__c = 'TestCredential'
        );
        insert llm;

        ApexAgent_Agent__c agent = new ApexAgent_Agent__c(
            Name           = 'Test Agent',
            LLM__c         = llm.Id,
            Max_Tokens__c  = 1000
        );
        insert agent;

        GetRecordDetails tool   = new GetRecordDetails();
        Map<String, Object> res = (Map<String, Object>) tool.execute(
            new Map<String, Object>{ 'recordId' => String.valueOf(agent.Id) }
        );

        // Custom lookup field itself
        Assert.areEqual(String.valueOf(llm.Id), res.get('LLM__c'), 'LLM__c should hold the LLM record Id');
        // Enriched relationship — JSON.serialize produces LLM__r as a nested map
        Map<String, Object> llmRel = (Map<String, Object>) res.get('LLM__r');
        Assert.isNotNull(llmRel,                        'LLM__r should be present via enrichment');
        Assert.areEqual('Test LLM', llmRel.get('Name'), 'LLM__r.Name should match the LLM record name');
    }
}
