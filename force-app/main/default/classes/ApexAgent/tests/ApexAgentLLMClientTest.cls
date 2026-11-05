/**
 * Verifies ApexAgentLLMClient's send and retry loop: the endpoint and body come
 * from the adapter, network and retryable failures retry up to the cap, and
 * non-retryable failures (a 400, an exhausted balance, a long Retry-After)
 * fail without more attempts.
 */
@IsTest
private class ApexAgentLLMClientTest {

    private static ApexAgentLLMProvider buildProvider(String path) {
        ApexAgentConfigTypes.AgentConfig cfg = new ApexAgentConfigTypes.AgentConfig();
        cfg.providerName        = 'Test Provider';
        cfg.providerType        = 'OpenRouter';
        cfg.namedCredential     = 'TestCred';
        cfg.chatCompletionsPath = path;
        cfg.modelApiName        = 'test-model';
        cfg.maxTokens           = 1000;
        return ApexAgentLLMProviderFactory.create(cfg);
    }

    private static ApexAgentLLMTypes.LLMResult callWith(ApexAgentLLMCalloutMock mock, String path) {
        Test.setMock(HttpCalloutMock.class, mock);
        return ApexAgentLLMClient.call(buildProvider(path), new List<Object>(), new List<Map<String, Object>>());
    }

    private static String failureOf(ApexAgentLLMCalloutMock mock) {
        try {
            callWith(mock, '/api/v1/chat/completions');
            Assert.fail('Expected a CalloutException');
        } catch (CalloutException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void testSuccessSendsAdapterBodyAndParsesResult() {
        ApexAgentLLMCalloutMock mock = new ApexAgentLLMCalloutMock(200, ApexAgentLLMCalloutMock.stopResponse('Hi there'));

        Test.startTest();
        ApexAgentLLMTypes.LLMResult result = callWith(mock, '/api/v1/chat/completions');
        ApexAgentLLMCalloutMock blankPathMock = new ApexAgentLLMCalloutMock(200, ApexAgentLLMCalloutMock.stopResponse('Hi'));
        callWith(blankPathMock, null);
        Test.stopTest();

        Assert.areEqual('callout:TestCred/api/v1/chat/completions', mock.lastEndpoint, 'Endpoint should be credential plus path');
        Assert.areEqual('callout:TestCred', blankPathMock.lastEndpoint, 'A blank path should call the Named Credential URL as-is');
        Map<String, Object> sent = mock.requestBody(0);
        Assert.areEqual('test-model', sent.get('model'), 'The model should be sent');
        Assert.areEqual(1000, sent.get('max_completion_tokens'), 'Max tokens should be sent');
        Assert.isFalse(sent.containsKey('tools'), 'No tools key when there are no tools');
        Assert.areEqual('Hi there', result.content, 'Content should be parsed');
        Assert.areEqual('stop', result.finishReason, 'Finish reason should be parsed');
        Assert.areEqual(10, result.usage.inputTokens, 'Input tokens should be parsed');
        Assert.isFalse(result.hasToolCalls(), 'A plain answer has no tool calls');
    }

    @IsTest
    static void testFailuresRetryOnlyWhenWorthIt() {
        ApexAgentLLMCalloutMock badRequest = new ApexAgentLLMCalloutMock(400, '{"error":"bad request"}');
        ApexAgentLLMCalloutMock unavailable = new ApexAgentLLMCalloutMock(503, '{"error":"unavailable"}');
        ApexAgentLLMCalloutMock noBalance = new ApexAgentLLMCalloutMock(429,
            '{"error":{"code":"insufficient_quota","message":"You exceeded your current quota"}}');
        ApexAgentLLMCalloutMock longWait = new ApexAgentLLMCalloutMock(429, '{"error":"rate limited"}')
            .withHeader('Retry-After', '30');
        ApexAgentLLMCalloutMock recovers = new ApexAgentLLMCalloutMock(
            new List<Integer>{ 502, 200 },
            new List<String>{ '{"error":"bad gateway"}', ApexAgentLLMCalloutMock.stopResponse('Back') }
        ).withHeader('Retry-After', '1');

        Test.startTest();
        String badRequestError = failureOf(badRequest);
        String unavailableError = failureOf(unavailable);
        String noBalanceError = failureOf(noBalance);
        String longWaitError = failureOf(longWait);
        ApexAgentLLMTypes.LLMResult recovered = callWith(recovers, '/api/v1/chat/completions');
        Test.stopTest();

        Assert.isTrue(badRequestError.contains('non-retryable status'), badRequestError);
        Assert.areEqual(1, badRequest.requestBodies.size(), 'A 400 must not be retried');
        Assert.isTrue(unavailableError.contains('attempt(s)'), unavailableError);
        Assert.areEqual(4, unavailable.requestBodies.size(), 'A 503 should be sent once and retried three times');
        Assert.isTrue(noBalanceError.contains('non-retryable status'), noBalanceError);
        Assert.areEqual(1, noBalance.requestBodies.size(), 'An exhausted balance must not be retried');
        Assert.isTrue(longWaitError.contains('wait 30 seconds'), longWaitError);
        Assert.areEqual(1, longWait.requestBodies.size(), 'A long Retry-After should fail instead of retrying at once');
        Assert.areEqual('Back', recovered.content, 'A short Retry-After should be retried');
        Assert.areEqual(2, recovers.requestBodies.size(), 'One retry should be enough once the provider recovers');
    }
}
