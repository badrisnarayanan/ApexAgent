@IsTest
private class GetRecordDetailsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        try {
            run('   ');
            Assert.fail('Expected exception for blank recordId');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        try {
            run('not-a-valid-id');
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

        Map<String, Object> res = run(String.valueOf(acc.Id));

        // JSON.serialize produces flat fields + nested 'attributes' with type info
        Assert.areEqual('Test Account GetRecordDetails', res.get('Name'), 'Name should match');
        Assert.areEqual(String.valueOf(acc.Id), res.get('Id'), 'Id should match');
        Map<String, Object> attrs = (Map<String, Object>) res.get('attributes');
        Assert.areEqual('Account', attrs.get('type'), 'attributes.type should be Account');
    }

    // ─── Bulk-safe: multiple records across object types in one call ─────────────

    @IsTest
    static void testMultipleRecordsAcrossObjectTypes() {
        Account acc = new Account(Name = 'Bulk Test Account');
        insert acc;
        ApexAgent_LLM__c llm = new ApexAgent_LLM__c(
            Name = 'Bulk Test LLM', Model_API_Name__c = 'test-model',
            Family__c = 'Anthropic', Named_Credential__c = 'TestCredential'
        );
        insert llm;

        List<GetRecordDetails.Input> inputs = new List<GetRecordDetails.Input>{
            buildInput(String.valueOf(acc.Id)),
            buildInput(String.valueOf(llm.Id))
        };
        List<GetRecordDetails.Output> outputs = GetRecordDetails.run(inputs);

        Assert.areEqual(2, outputs.size(), 'Should return one output per input, in order');
        Map<String, Object> accResult = (Map<String, Object>) JSON.deserializeUntyped(outputs[0].resultJson);
        Map<String, Object> llmResult = (Map<String, Object>) JSON.deserializeUntyped(outputs[1].resultJson);
        Assert.areEqual('Bulk Test Account', accResult.get('Name'), 'First output should be the Account');
        Assert.areEqual('Bulk Test LLM', llmResult.get('Name'), 'Second output should be the LLM');
    }

    // ─── Field filtering: long text areas excluded ────────────────────────────────

    @IsTest
    static void testFieldFiltering() {
        // Account.Description is a TEXTAREA with length 32000 — must be excluded
        Account acc = new Account(Name = 'Filter Test', Description = 'Some description text');
        insert acc;

        Map<String, Object> res = run(String.valueOf(acc.Id));

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

        Map<String, Object> res = run(String.valueOf(ghostId));

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

        Map<String, Object> res = run(String.valueOf(agent.Id));

        // Custom lookup field itself
        Assert.areEqual(String.valueOf(llm.Id), res.get('LLM__c'), 'LLM__c should hold the LLM record Id');
        // Enriched relationship — JSON.serialize produces LLM__r as a nested map
        Map<String, Object> llmRel = (Map<String, Object>) res.get('LLM__r');
        Assert.isNotNull(llmRel,                        'LLM__r should be present via enrichment');
        Assert.areEqual('Test LLM', llmRel.get('Name'), 'LLM__r.Name should match the LLM record name');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static GetRecordDetails.Input buildInput(String recordId) {
        GetRecordDetails.Input inp = new GetRecordDetails.Input();
        inp.recordId = recordId;
        return inp;
    }

    private static Map<String, Object> run(String recordId) {
        List<GetRecordDetails.Output> out = GetRecordDetails.run(new List<GetRecordDetails.Input>{ buildInput(recordId) });
        return (Map<String, Object>) JSON.deserializeUntyped(out[0].resultJson);
    }
}
