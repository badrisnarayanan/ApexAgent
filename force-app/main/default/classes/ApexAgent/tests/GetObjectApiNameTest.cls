@IsTest
private class GetObjectApiNameTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        try {
            GetObjectApiName.run(new List<GetObjectApiName.Input>{ buildInput(null) });
            Assert.fail('Expected exception for blank recordId');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        try {
            GetObjectApiName.run(new List<GetObjectApiName.Input>{ buildInput('   ') });
            Assert.fail('Expected exception for blank recordId');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        try {
            GetObjectApiName.run(new List<GetObjectApiName.Input>{ buildInput('not-a-valid-id') });
            Assert.fail('Expected exception for invalid ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('not a valid Salesforce ID'), 'Message should mention invalid ID');
        }
    }

    // ─── Happy path — direct static call ─────────────────────────────────────────

    @IsTest
    static void testHappyPathDirectCall() {
        Account acc = new Account(Name = 'Test GetObjectApiName');
        insert acc;

        ApexAgent_LLM__c llm = new ApexAgent_LLM__c(
            Name                = 'Test LLM',
            Model_API_Name__c   = 'test-model',
            Family__c           = 'Anthropic',
            Named_Credential__c = 'TestCredential'
        );
        insert llm;

        List<GetObjectApiName.Output> accResults = GetObjectApiName.run(
            new List<GetObjectApiName.Input>{ buildInput(String.valueOf(acc.Id)) }
        );
        List<GetObjectApiName.Output> llmResults = GetObjectApiName.run(
            new List<GetObjectApiName.Input>{ buildInput(String.valueOf(llm.Id)) }
        );

        Assert.areEqual('Account', resultMap(accResults[0]).get('objectApiName'), 'objectApiName should be Account');
        Assert.areEqual('ApexAgent_LLM__c', resultMap(llmResults[0]).get('objectApiName'), 'objectApiName should be ApexAgent_LLM__c');
    }

    // ─── Happy path — through the real Invocable.Action dispatch path ────────────

    @IsTest
    static void testHappyPathViaInvocableAction() {
        Account acc = new Account(Name = 'Test GetObjectApiName Invocable');
        insert acc;

        Invocable.Action action = Invocable.Action.createCustomAction('apex', 'GetObjectApiName');
        action.setInvocations(new List<Map<String, Object>>{
            new Map<String, Object>{ 'recordId' => String.valueOf(acc.Id) }
        });

        Test.startTest();
        List<Invocable.Action.Result> results = action.invoke();
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess(), 'Action invocation should succeed');
        Map<String, Object> outputs = results[0].getOutputParameters();
        Map<String, Object> res = (Map<String, Object>) JSON.deserializeUntyped((String) outputs.get('resultJson'));
        Assert.areEqual('Account', res.get('objectApiName'), 'objectApiName should be Account');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static GetObjectApiName.Input buildInput(String recordId) {
        GetObjectApiName.Input inp = new GetObjectApiName.Input();
        inp.recordId = recordId;
        return inp;
    }

    private static Map<String, Object> resultMap(GetObjectApiName.Output output) {
        return (Map<String, Object>) JSON.deserializeUntyped(output.resultJson);
    }
}
