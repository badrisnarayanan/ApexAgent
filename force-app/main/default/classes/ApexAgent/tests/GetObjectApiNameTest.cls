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
        // The running user's Id covers a standard object without inserting one
        ApexAgent_LLM__c llm = ApexAgentTestDataFactory.newLlm('Test LLM');
        insert llm;

        List<GetObjectApiName.Output> userResults = GetObjectApiName.run(
            new List<GetObjectApiName.Input>{ buildInput(UserInfo.getUserId()) }
        );
        List<GetObjectApiName.Output> llmResults = GetObjectApiName.run(
            new List<GetObjectApiName.Input>{ buildInput(String.valueOf(llm.Id)) }
        );

        Assert.areEqual('User', userResults[0].objectApiName, 'objectApiName should be User');
        Assert.areEqual('ApexAgent_LLM__c', llmResults[0].objectApiName, 'objectApiName should be ApexAgent_LLM__c');
    }

    // ─── Happy path — through the real Invocable.Action dispatch path ────────────

    @IsTest
    static void testHappyPathViaInvocableAction() {
        Invocable.Action action = Invocable.Action.createCustomAction('apex', 'GetObjectApiName');
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

    private static GetObjectApiName.Input buildInput(String recordId) {
        GetObjectApiName.Input inp = new GetObjectApiName.Input();
        inp.recordId = recordId;
        return inp;
    }
}
