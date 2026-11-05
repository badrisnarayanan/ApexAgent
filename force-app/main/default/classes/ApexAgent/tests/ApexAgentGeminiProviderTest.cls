/**
 * Gemini adapter (AI Studio): the thought signature on the first
 * tool call, the skip value when a response has none, which stored tokens go
 * back on replayed turns, and reasoning tokens left out of completion_tokens.
 */
@IsTest
private class ApexAgentGeminiProviderTest {

    private static ApexAgentLLMProvider provider() {
        return ApexAgentLLMProviderFactory.create(ApexAgentTestDataFactory.newAgentConfig('Google_AI_Studio'));
    }

    private static Map<String, Object> toolCall(String id, String signature) {
        Map<String, Object> call = new Map<String, Object>{
            'id' => id, 'type' => 'function',
            'function' => new Map<String, Object>{ 'name' => 'ApexAgentGetOrgInfo', 'arguments' => '{}' }
        };
        if (signature != null) {
            call.put('extra_content', new Map<String, Object>{
                'google' => new Map<String, Object>{ 'thought_signature' => signature }
            });
        }
        return call;
    }

    private static String responseWith(List<Object> toolCalls) {
        return JSON.serialize(new Map<String, Object>{
            'choices' => new List<Object>{ new Map<String, Object>{
                'finish_reason' => 'tool_calls',
                'message' => new Map<String, Object>{ 'role' => 'assistant', 'tool_calls' => toolCalls }
            } },
            'usage' => new Map<String, Object>{
                'prompt_tokens' => 8316, 'completion_tokens' => 40, 'total_tokens' => 8556,
                'prompt_tokens_details' => new Map<String, Object>{ 'cached_tokens' => 6269 }
            }
        });
    }

    private static String signatureOn(ApexAgentApiTypes.ToolCall call) {
        Map<String, Object> google = (Map<String, Object>) call.extra_content?.get('google');
        return google == null ? null : (String) google.get('thought_signature');
    }

    @IsTest
    static void testThoughtSignatures() {
        ApexAgentLLMProvider adapter = provider();

        ApexAgentLLMTypes.LLMResult signed = adapter.parseResponse(responseWith(new List<Object>{
            toolCall('call_1', 'sig-abc'), toolCall('call_2', null)
        }));
        Assert.areEqual('google:sig-abc', signed.continuityToken, 'The signature should be tagged with its format');
        ApexAgentApiTypes.ChatMessage turn = ApexAgentOrchestratorUtils.buildAssistantTurn(signed, adapter);
        Assert.areEqual('sig-abc', signatureOn(turn.tool_calls[0]), 'The signature should go back on the first call');
        Assert.isNull(signatureOn(turn.tool_calls[1]), 'Only the first parallel call carries the signature');
        Map<String, Object> wire = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(turn, true));
        Map<String, Object> wireCall = (Map<String, Object>) ((List<Object>) wire.get('tool_calls'))[0];
        Assert.isTrue(JSON.serialize(wireCall.get('extra_content')).contains('"thought_signature":"sig-abc"'),
            'The signature should be serialized at extra_content.google.thought_signature');

        ApexAgentLLMTypes.LLMResult unsigned = adapter.parseResponse(responseWith(new List<Object>{ toolCall('call_3', null) }));
        Assert.isNull(unsigned.continuityToken, 'The skip value is not a real signature, so nothing should be logged');
        Assert.areEqual(ApexAgentGeminiProvider.SKIP_SIGNATURE, signatureOn(unsigned.toolCalls[0]),
            'A call with no signature should carry the skip value for the turn in progress');

        ApexAgentApiTypes.ChatMessage replayed = new ApexAgentApiTypes.ChatMessage();
        replayed.tool_calls = new List<ApexAgentApiTypes.ToolCall>{ new ApexAgentApiTypes.ToolCall() };
        adapter.attachContinuity(replayed, 'openrouter:enc-1');
        Assert.isNull(replayed.tool_calls[0].extra_content, 'A token written by another provider should be ignored');
        adapter.attachContinuity(replayed, 'google:sig-old');
        Assert.areEqual('sig-old', signatureOn(replayed.tool_calls[0]), 'Its own stored signature should go back on replay');
        ApexAgentApiTypes.ChatMessage noCalls = new ApexAgentApiTypes.ChatMessage();
        adapter.attachContinuity(noCalls, 'google:sig-old');
        Assert.isNull(noCalls.tool_calls, 'A turn without tool calls should be left alone');
    }

    @IsTest
    static void testUsageAddsUnreportedReasoning() {
        ApexAgentLLMTypes.LLMResult result = provider().parseResponse(responseWith(new List<Object>{ toolCall('c', 'sig') }));

        Assert.areEqual(8316, result.usage.inputTokens, 'Input tokens');
        Assert.areEqual(6269, result.usage.cachedInputTokens, 'Cache hits are reported in the OpenAI field');
        Assert.areEqual(200, result.usage.reasoningTokens, 'Reasoning is total minus prompt minus completion');
        Assert.areEqual(240, result.usage.outputTokens, 'Output should include the reasoning');
        Assert.areEqual(8556, result.usage.totalTokens, 'Total tokens');
        Assert.isNull(result.usage.providerCost, 'Gemini reports no cost');

        ApexAgentConfigTypes.AgentConfig plain = ApexAgentTestDataFactory.newAgentConfig('Google_AI_Studio');
        plain.supportsReasoning = false;
        Map<String, Object> body = ApexAgentLLMProviderFactory.create(plain)
            .buildRequestBody(new List<Object>(), new List<Map<String, Object>>());
        Assert.isFalse(body.containsKey('reasoning_effort'),
            'Gemini 3 can\'t turn thinking off, so no effort is sent when the LLM has reasoning off');
    }
}
