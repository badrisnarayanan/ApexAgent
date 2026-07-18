/**
 * Verifies ApexAgentLLMClient's retry classification: network-level and
 * retryable HTTP statuses retry up to the cap, non-retryable statuses fail
 * immediately, and successful responses deserialize correctly.
 */
@IsTest
private class ApexAgentLLMClientTest {

    private static ApexAgentConfigTypes.AgentConfig buildConfig() {
        ApexAgentConfigTypes.AgentConfig cfg = new ApexAgentConfigTypes.AgentConfig();
        cfg.namedCredential = 'TestCred';
        cfg.chatCompletionsPath = '/v1/messages';
        cfg.modelApiName = 'test-model';
        cfg.maxTokens = 1000;
        return cfg;
    }

    @IsTest
    static void testCallSuccessDeserializesChoicesAndUsage() {
        Test.setMock(HttpCalloutMock.class,
            new ApexAgentLLMCalloutMock(200, ApexAgentLLMCalloutMock.stopResponse('Hi there')));

        Test.startTest();
        ApexAgentApiTypes.ChatCompletionResponse resp =
            ApexAgentLLMClient.call(buildConfig(), new List<Object>(), new List<Map<String, Object>>());
        Test.stopTest();

        Assert.isNotNull(resp.choices, 'choices should deserialize');
        Assert.areEqual(1, resp.choices.size(), 'Should have one choice');
        Assert.areEqual('Hi there', resp.choices[0].message.content, 'Content should match');
        Assert.isNotNull(resp.usage, 'usage should deserialize');
        Assert.areEqual(10, resp.usage.prompt_tokens, 'prompt_tokens should match');
    }

    @IsTest
    static void testCallEmptyChoicesDeserializesToEmptyListNotNull() {
        Test.setMock(HttpCalloutMock.class,
            new ApexAgentLLMCalloutMock(200, ApexAgentLLMCalloutMock.emptyChoicesResponse()));

        Test.startTest();
        ApexAgentApiTypes.ChatCompletionResponse resp =
            ApexAgentLLMClient.call(buildConfig(), new List<Object>(), new List<Map<String, Object>>());
        Test.stopTest();

        Assert.isNotNull(resp.choices, 'choices should deserialize to an empty list, not null');
        Assert.isTrue(resp.choices.isEmpty(), 'choices should be empty');
        Assert.isNull(resp.usage, 'usage should be null when absent from the payload');
    }

    @IsTest
    static void testCallNonRetryableStatusFailsImmediately() {
        Test.setMock(HttpCalloutMock.class, new ApexAgentLLMCalloutMock(400, '{"error":"bad request"}'));

        Test.startTest();
        try {
            ApexAgentLLMClient.call(buildConfig(), new List<Object>(), new List<Map<String, Object>>());
            Assert.fail('Expected a CalloutException for a non-retryable status');
        } catch (CalloutException e) {
            Assert.isTrue(e.getMessage().contains('non-retryable status'),
                'Should fail via the immediate non-retryable path: ' + e.getMessage());
            Assert.isFalse(e.getMessage().contains('attempt(s)'),
                'A 400 must not be retried: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testCallRetryableStatusExhaustsRetriesThenFails() {
        Test.setMock(HttpCalloutMock.class, new ApexAgentLLMCalloutMock(503, '{"error":"unavailable"}'));

        Test.startTest();
        try {
            ApexAgentLLMClient.call(buildConfig(), new List<Object>(), new List<Map<String, Object>>());
            Assert.fail('Expected a CalloutException after exhausting retries');
        } catch (CalloutException e) {
            Assert.isTrue(e.getMessage().contains('attempt(s)'),
                'A 503 should retry then fail with the exhaustion message: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
