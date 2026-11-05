/**
 * OpenAI and Azure OpenAI adapter: the reasoning_effort it sends, the one
 * corrected resend after a reasoning_effort rejection (remembered for later
 * calls), and usage parsing. Each scenario uses its own model name, because
 * remembered corrections are keyed by provider and model.
 */
@IsTest
private class ApexAgentOpenAIProviderTest {

    private static final String TOOLS_WITH_EFFORT_ERROR = JSON.serialize(new Map<String, Object>{
        'error' => new Map<String, Object>{
            'message' => 'Function tools with reasoning_effort are not supported for gpt-x in /v1/chat/completions. '
                + 'To use function tools, use /v1/responses or set reasoning_effort to \'none\'.',
            'type' => 'invalid_request_error',
            'param' => 'reasoning_effort',
            'code' => null
        }
    });

    private static final String UNSUPPORTED_EFFORT_ERROR = JSON.serialize(new Map<String, Object>{
        'error' => new Map<String, Object>{
            'message' => 'Unrecognized request argument supplied: reasoning_effort',
            'type' => 'invalid_request_error',
            'param' => null,
            'code' => 'unsupported_parameter'
        }
    });

    private static ApexAgentLLMProvider provider(String model, Boolean supportsReasoning, String effort) {
        ApexAgentConfigTypes.AgentConfig cfg = ApexAgentTestDataFactory.newAgentConfig('Azure_OpenAI');
        cfg.modelApiName      = model;
        cfg.supportsReasoning = supportsReasoning;
        cfg.reasoningEffort   = effort;
        return ApexAgentLLMProviderFactory.create(cfg);
    }

    private static Object effortSent(ApexAgentLLMProvider adapter) {
        return adapter.buildRequestBody(new List<Object>(), new List<Map<String, Object>>()).get('reasoning_effort');
    }

    private static List<Map<String, Object>> oneTool() {
        return new List<Map<String, Object>>{ new Map<String, Object>{
            'type' => 'function',
            'function' => new Map<String, Object>{ 'name' => 'ApexAgentGetOrgInfo', 'parameters' => new Map<String, Object>() }
        } };
    }

    @IsTest
    static void testReasoningEffortSent() {
        Assert.isNull(effortSent(provider('m-plain', false, null)),
            'An LLM without reasoning should leave the field out, because non-reasoning models reject it');
        Assert.areEqual('none', effortSent(provider('m-disabled', true, 'disabled')),
            'An agent with reasoning disabled should send none');
        Assert.areEqual('high', effortSent(provider('m-high', true, 'high')), 'A set effort should be sent as-is');
        Assert.isNull(effortSent(provider('m-default', true, null)), 'No effort set should leave the field out');

        Map<String, Object> body = provider('m-tools', true, 'low').buildRequestBody(new List<Object>(), oneTool());
        Assert.areEqual('auto', body.get('tool_choice'), 'Tools should be offered with tool_choice auto');
        Assert.areEqual(1, ((List<Object>) body.get('tools')).size(), 'Tools should be sent');
        Assert.areEqual('callout:TestCredential/v1/chat/completions', provider('m-url', true, null).endpoint(),
            'The endpoint should be the credential plus the path');
    }

    @IsTest
    static void testToolsWithReasoningRejectionResendsWithNoneAndRemembers() {
        ApexAgentLLMCalloutMock mock = new ApexAgentLLMCalloutMock(
            new List<Integer>{ 400, 200 },
            new List<String>{ TOOLS_WITH_EFFORT_ERROR, ApexAgentLLMCalloutMock.stopResponse('Done') }
        );
        Test.setMock(HttpCalloutMock.class, mock);
        ApexAgentLLMProvider adapter = provider('gpt-new', true, 'low');

        Test.startTest();
        ApexAgentLLMTypes.LLMResult result = ApexAgentLLMClient.call(adapter, new List<Object>(), oneTool());
        ApexAgentLLMClient.call(provider('gpt-new', true, 'low'), new List<Object>(), oneTool());
        Object effortAfterFix = effortSent(provider('gpt-new', true, 'medium'));
        Test.stopTest();

        Assert.areEqual('Done', result.content, 'The corrected resend should succeed');
        Assert.areEqual(3, mock.requestBodies.size(), 'One rejected call, its resend, then one call for the next request');
        Assert.areEqual('low', mock.requestBody(0).get('reasoning_effort'), 'The first request sends the configured effort');
        Assert.areEqual('none', mock.requestBody(1).get('reasoning_effort'), 'The resend should use none');
        Assert.areEqual('none', mock.requestBody(2).get('reasoning_effort'),
            'A later call for the same model should send none straight away');
        Assert.areEqual(1, adapter.getWarnings().size(), 'The admin should be warned once');
        Assert.isTrue(adapter.getWarnings()[0].contains('Reasoning Effort to disabled'), adapter.getWarnings()[0]);
        Assert.areEqual('medium', effortAfterFix, 'Changed reasoning settings should not be overridden by the old correction');
    }

    @IsTest
    static void testOtherRejectionsOfReasoningEffort() {
        ApexAgentLLMCalloutMock omitMock = new ApexAgentLLMCalloutMock(
            new List<Integer>{ 400, 200 },
            new List<String>{ UNSUPPORTED_EFFORT_ERROR, ApexAgentLLMCalloutMock.stopResponse('Done') }
        );
        ApexAgentLLMCalloutMock otherParamMock = new ApexAgentLLMCalloutMock(400,
            '{"error":{"message":"Invalid value","param":"messages","type":"invalid_request_error"}}');
        ApexAgentLLMCalloutMock notJsonMock = new ApexAgentLLMCalloutMock(400, 'Bad Request');
        ApexAgentLLMProvider oldModel = provider('gpt-old', true, 'low');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, omitMock);
        ApexAgentLLMClient.call(oldModel, new List<Object>(), oneTool());
        Object effortAfterOmit = effortSent(provider('gpt-old', true, 'low'));
        List<String> failures = new List<String>();
        for (ApexAgentLLMCalloutMock failing : new List<ApexAgentLLMCalloutMock>{ otherParamMock, notJsonMock }) {
            Test.setMock(HttpCalloutMock.class, failing);
            try {
                ApexAgentLLMClient.call(provider('gpt-other', true, 'low'), new List<Object>(), oneTool());
            } catch (CalloutException e) {
                failures.add(e.getMessage());
            }
        }
        Test.stopTest();

        Assert.areEqual('low', omitMock.requestBody(0).get('reasoning_effort'), 'The first request sends the configured effort');
        Assert.isFalse(omitMock.requestBody(1).containsKey('reasoning_effort'),
            'A rejection that names the field only in its message should be resent without it');
        Assert.isNull(effortAfterOmit, 'Later requests for that model should leave the field out');
        Assert.isTrue(oldModel.getWarnings()[0].contains('without it'), oldModel.getWarnings()[0]);
        Assert.areEqual(2, failures.size(), 'Other 400s should fail');
        Assert.areEqual(1, otherParamMock.requestBodies.size(), 'A 400 about another parameter must not be resent');
        Assert.areEqual(1, notJsonMock.requestBodies.size(), 'A 400 with no JSON body must not be resent');
    }

    @IsTest
    static void testParsesToolCallsAndUsage() {
        String body = JSON.serialize(new Map<String, Object>{
            'choices' => new List<Object>{ new Map<String, Object>{
                'finish_reason' => 'tool_calls',
                'message' => new Map<String, Object>{
                    'role' => 'assistant',
                    'content' => null,
                    'tool_calls' => new List<Object>{ new Map<String, Object>{
                        'id' => 'call_1', 'type' => 'function',
                        'function' => new Map<String, Object>{ 'name' => 'ApexAgentGetOrgInfo', 'arguments' => '{}' }
                    } }
                }
            } },
            'usage' => new Map<String, Object>{
                'prompt_tokens' => 7225, 'completion_tokens' => 300, 'total_tokens' => 7525,
                'prompt_tokens_details' => new Map<String, Object>{ 'cached_tokens' => 6144 },
                'completion_tokens_details' => new Map<String, Object>{ 'reasoning_tokens' => 256 }
            }
        });

        ApexAgentLLMTypes.LLMResult result = provider('m-parse', true, 'low').parseResponse(body);

        Assert.isTrue(result.hasToolCalls(), 'Tool calls should be parsed');
        Assert.areEqual('call_1', result.toolCalls[0].id, 'Tool call id');
        Assert.areEqual('ApexAgentGetOrgInfo', result.toolCalls[0].function.name, 'Tool name');
        Assert.isNull(result.toolCalls[0].extra_content, 'OpenAI tool calls carry no extras');
        Assert.isNull(result.continuityToken, 'OpenAI needs no continuity token');
        Assert.isNull(result.thought, 'OpenAI chat completions returns no reasoning text');
        Assert.areEqual(7225, result.usage.inputTokens, 'Input tokens');
        Assert.areEqual(6144, result.usage.cachedInputTokens, 'Cached tokens');
        Assert.areEqual(300, result.usage.outputTokens, 'completion_tokens already includes reasoning');
        Assert.areEqual(256, result.usage.reasoningTokens, 'Reasoning tokens');
        Assert.areEqual(7525, result.usage.totalTokens, 'Total tokens');
        Assert.isNull(result.usage.providerCost, 'OpenAI reports no cost');

        try {
            provider('m-parse', true, 'low').parseResponse('{"choices":[],"error":{"message":"overloaded"}}');
            Assert.fail('A response with no choices should be rejected');
        } catch (ApexAgentLLMProvider.ProviderException e) {
            Assert.isTrue(e.getMessage().contains('no choices') && e.getMessage().contains('overloaded'), e.getMessage());
        }

        try {
            provider('m-bad', true, null).parseResponse('{"choices":[null],"error":{"message":"upstream failed"}}');
            Assert.fail('A choice that is not an object should throw');
        } catch (ApexAgentLLMProvider.ProviderException e) {
            Assert.isTrue(e.getMessage().contains('upstream failed'), 'The provider error should be in the message: ' + e.getMessage());
        }
    }
}
