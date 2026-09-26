@IsTest
private class ApexAgentGetObjectApiNameTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        try {
            ApexAgentGetObjectApiName.run(new List<ApexAgentGetObjectApiName.Input>{ buildInput(null) });
            Assert.fail('Expected exception for blank recordId');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        try {
            ApexAgentGetObjectApiName.run(new List<ApexAgentGetObjectApiName.Input>{ buildInput('   ') });
            Assert.fail('Expected exception for blank recordId');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        try {
            ApexAgentGetObjectApiName.run(new List<ApexAgentGetObjectApiName.Input>{ buildInput('not-a-valid-id') });
            Assert.fail('Expected exception for invalid ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('not a valid Salesforce ID'), 'Message should mention invalid ID');
        }
    }

    // ─── Happy path — direct static call ─────────────────────────────────────────

    @IsTest
    static void testHappyPathDirectCall() {
        // The running user's Id covers a standard object without inserting one
        ApexAgent_LLM__c llm = ApexAgentTestDataFactory.newLlm('Test LLM');
        insert llm;

        List<ApexAgentGetObjectApiName.Output> userResults = ApexAgentGetObjectApiName.run(
            new List<ApexAgentGetObjectApiName.Input>{ buildInput(UserInfo.getUserId()) }
        );
        List<ApexAgentGetObjectApiName.Output> llmResults = ApexAgentGetObjectApiName.run(
            new List<ApexAgentGetObjectApiName.Input>{ buildInput(String.valueOf(llm.Id)) }
        );

        Assert.areEqual('User', userResults[0].objectApiName, 'objectApiName should be User');
        Assert.areEqual('ApexAgent_LLM__c', llmResults[0].objectApiName, 'objectApiName should be ApexAgent_LLM__c');
    }

    // ─── Happy path — through the real Invocable.Action dispatch path ────────────

    @IsTest
    static void testHappyPathViaInvocableAction() {
        Invocable.Action action = Invocable.Action.createCustomAction('apex', 'ApexAgentGetObjectApiName');
        action.setInvocations(new List<Map<String, Object>>{
            new Map<String, Object>{ 'recordId' => UserInfo.getUserId() }
        });

        Test.startTest();
        List<Invocable.Action.Result> results = action.invoke();
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess(), 'Action invocation should succeed');
        Map<String, Object> outputs = results[0].getOutputParameters();
        Assert.areEqual('User', outputs.get('objectApiName'), 'objectApiName should be User');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static ApexAgentGetObjectApiName.Input buildInput(String recordId) {
        ApexAgentGetObjectApiName.Input inp = new ApexAgentGetObjectApiName.Input();
        inp.recordId = recordId;
        return inp;
    }
}
