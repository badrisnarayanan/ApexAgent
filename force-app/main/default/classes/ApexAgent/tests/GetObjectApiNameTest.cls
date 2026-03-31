@IsTest
private class GetObjectApiNameTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        GetObjectApiName tool = new GetObjectApiName();

        try {
            tool.execute(null);
            Assert.fail('Expected exception for null input');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('null'), 'Message should mention null');
        }

        try {
            tool.execute(new Map<String, Object>());
            Assert.fail('Expected exception for missing recordId');
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

    // ─── Happy path ──────────────────────────────────────────────────────────────

    @IsTest
    static void testHappyPath() {
        Account acc = new Account(Name = 'Test GetObjectApiName');
        insert acc;

        GetObjectApiName tool   = new GetObjectApiName();
        Map<String, Object> res = (Map<String, Object>) tool.execute(
            new Map<String, Object>{ 'recordId' => String.valueOf(acc.Id) }
        );

        Assert.areEqual('Account', res.get('objectApiName'), 'objectApiName should be Account');

        // Custom object ID
        ApexAgent_LLM__c llm = new ApexAgent_LLM__c(
            Name                = 'Test LLM',
            Model_API_Name__c   = 'test-model',
            Family__c           = 'Anthropic',
            Named_Credential__c = 'TestCredential'
        );
        insert llm;

        res = (Map<String, Object>) tool.execute(
            new Map<String, Object>{ 'recordId' => String.valueOf(llm.Id) }
        );

        Assert.areEqual('ApexAgent_LLM__c', res.get('objectApiName'), 'objectApiName should be ApexAgent_LLM__c');
    }
}
