@IsTest
private class ApexAgentGetRecordDetailsTest {

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

    // ─── Happy path ──────────────────────────────────────────────────────────────

    @IsTest
    static void testHappyPath() {
        ApexAgent_Topic__c topic = ApexAgentTestDataFactory.newTopic('Test Topic ApexAgentGetRecordDetails', 'get_record_details');
        insert topic;

        Map<String, Object> res = run(String.valueOf(topic.Id));

        // JSON.serialize produces flat fields + nested 'attributes' with type info
        Assert.areEqual('Test Topic ApexAgentGetRecordDetails', res.get('Name'), 'Name should match');
        Assert.areEqual(String.valueOf(topic.Id), res.get('Id'), 'Id should match');
        Map<String, Object> attrs = (Map<String, Object>) res.get('attributes');
        Assert.areEqual('ApexAgent_Topic__c', attrs.get('type'), 'attributes.type should be ApexAgent_Topic__c');
    }

    // ─── Bulk-safe: multiple records across object types in one call ─────────────

    @IsTest
    static void testMultipleRecordsAcrossObjectTypes() {
        ApexAgent_Topic__c topic = ApexAgentTestDataFactory.newTopic('Bulk Test Topic', 'bulk_test_topic');
        insert topic;
        ApexAgent_LLM__c llm = ApexAgentTestDataFactory.newLlm('Bulk Test LLM');
        insert llm;

        List<ApexAgentGetRecordDetails.Input> inputs = new List<ApexAgentGetRecordDetails.Input>{
            buildInput(String.valueOf(topic.Id)),
            buildInput(String.valueOf(llm.Id))
        };
        List<ApexAgentGetRecordDetails.Output> outputs = ApexAgentGetRecordDetails.run(inputs);

        Assert.areEqual(2, outputs.size(), 'Should return one output per input, in order');
        Assert.areEqual('Bulk Test Topic', outputs[0].record.get('Name'), 'First output should be the Topic');
        Assert.areEqual('Bulk Test LLM', outputs[1].record.get('Name'), 'Second output should be the LLM');
    }

    // ─── Field filtering: long text areas excluded ────────────────────────────────

    @IsTest
    static void testFieldFiltering() {
        // ApexAgent_Topic__c.Description__c is a TEXTAREA with length 512 — must be excluded
        ApexAgent_Topic__c topic = ApexAgentTestDataFactory.newTopic('Filter Test', 'filter_test');
        topic.Description__c = 'Some description text';
        insert topic;

        Map<String, Object> res = run(String.valueOf(topic.Id));

        Assert.isFalse(res.containsKey('Description__c'), 'Description__c (long textarea) should be excluded');
        Assert.isTrue(res.containsKey('Name'),          'Name (short text) should be included');
    }

    // ─── Record not found ────────────────────────────────────────────────────────

    @IsTest
    static void testRecordNotFound() {
        // Generate a syntactically valid but non-existent record ID
        ApexAgent_Topic__c topic = ApexAgentTestDataFactory.newTopic('Temp', 'temp_topic');
        insert topic;
        Id ghostId = topic.Id;
        delete topic;

        ApexAgentGetRecordDetails.Output out = ApexAgentGetRecordDetails.run(
            new List<ApexAgentGetRecordDetails.Input>{ buildInput(String.valueOf(ghostId)) }
        )[0];

        Assert.areEqual(false, out.found, 'found should be false');
        Assert.isNotNull(out.message,     'message should be present');
        Assert.isNull(out.record,         'record should be absent');
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

    private static ApexAgentGetRecordDetails.Input buildInput(String recordId) {
        ApexAgentGetRecordDetails.Input inp = new ApexAgentGetRecordDetails.Input();
        inp.recordId = recordId;
        return inp;
    }

    private static Map<String, Object> run(String recordId) {
        List<ApexAgentGetRecordDetails.Output> out = ApexAgentGetRecordDetails.run(new List<ApexAgentGetRecordDetails.Input>{ buildInput(recordId) });
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(out[0].record));
    }
}
