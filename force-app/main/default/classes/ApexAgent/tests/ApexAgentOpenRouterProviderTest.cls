/**
 * OpenRouter adapter: reasoning text, the encrypted reasoning token and how it
 * goes back on an assistant turn, and the cost OpenRouter reports, with and
 * without the admin's own provider key (BYOK).
 */
@IsTest
private class ApexAgentOpenRouterProviderTest {

    private static ApexAgentLLMProvider provider() {
        return ApexAgentLLMProviderFactory.create(ApexAgentTestDataFactory.newAgentConfig('OpenRouter'));
    }

    private static String responseWith(Map<String, Object> message, Map<String, Object> usage) {
        return JSON.serialize(new Map<String, Object>{
            'choices' => new List<Object>{ new Map<String, Object>{ 'finish_reason' => 'tool_calls', 'message' => message } },
            'usage' => usage
        });
    }

    @IsTest
    static void testReasoningAndContinuity() {
        Map<String, Object> message = new Map<String, Object>{
            'role' => 'assistant',
            'reasoning_details' => new List<Object>{
                new Map<String, Object>{ 'type' => 'reasoning.summary', 'summary' => 'Look up the org first.' },
                new Map<String, Object>{ 'type' => 'reasoning.encrypted', 'data' => 'enc-123' }
            },
            'tool_calls' => new List<Object>{ new Map<String, Object>{
                'id' => 'tc1', 'type' => 'function',
                'function' => new Map<String, Object>{ 'name' => 'ApexAgentGetOrgInfo', 'arguments' => '{}' }
            } }
        };
        ApexAgentLLMProvider adapter = provider();

        ApexAgentLLMTypes.LLMResult result = adapter.parseResponse(responseWith(message, null));
        message.put('reasoning', 'Flat reasoning text.');
        ApexAgentLLMTypes.LLMResult flat = adapter.parseResponse(responseWith(message, null));

        Assert.areEqual('Look up the org first.', result.thought, 'The reasoning summary should be the thought');
        Assert.areEqual('Flat reasoning text.', flat.thought, 'A flat reasoning string should win over the summary');
        Assert.areEqual('openrouter:enc-123', result.continuityToken, 'The encrypted reasoning should be tagged with its format');

        ApexAgentApiTypes.ChatMessage turn = ApexAgentOrchestratorUtils.buildAssistantTurn(result, adapter);
        Assert.areEqual('assistant', turn.role, 'The turn should be an assistant turn');
        Assert.areEqual(1, turn.tool_calls.size(), 'The turn should carry the tool calls');
        Assert.areEqual('reasoning.encrypted', turn.reasoning_details[0].type, 'The token should go back as encrypted reasoning');
        Assert.areEqual('enc-123', turn.reasoning_details[0].data, 'The raw token should go back, without the format tag');

        ApexAgentApiTypes.ChatMessage foreign = new ApexAgentApiTypes.ChatMessage();
        adapter.attachContinuity(foreign, 'google:sig-1');
        adapter.attachContinuity(foreign, null);
        Assert.isNull(foreign.reasoning_details, 'A token written by another provider should be ignored');
    }

    @IsTest
    static void testReportedCost() {
        Map<String, Object> message = new Map<String, Object>{ 'role' => 'assistant', 'content' => 'Hi' };
        Map<String, Object> usage = new Map<String, Object>{
            'prompt_tokens' => 100, 'completion_tokens' => 20, 'total_tokens' => 120,
            'completion_tokens_details' => new Map<String, Object>{ 'reasoning_tokens' => 5 },
            'cost' => 0.00042
        };
        ApexAgentLLMProvider adapter = provider();

        ApexAgentLLMTypes.LLMResult paid = adapter.parseResponse(responseWith(message, usage));
        usage.put('cost', 0);
        usage.put('is_byok', true);
        usage.put('cost_details', new Map<String, Object>{ 'upstream_inference_cost' => 0.0013 });
        ApexAgentLLMTypes.LLMResult byok = adapter.parseResponse(responseWith(message, usage));
        usage.remove('cost');
        ApexAgentLLMTypes.LLMResult noCost = adapter.parseResponse(responseWith(message, usage));

        Assert.areEqual(0.00042, paid.usage.providerCost, 'usage.cost is what OpenRouter charged');
        Assert.areEqual(20, paid.usage.outputTokens, 'completion_tokens already includes reasoning');
        Assert.areEqual(5, paid.usage.reasoningTokens, 'Reasoning tokens');
        Assert.areEqual(0.0013, byok.usage.providerCost, 'With BYOK the upstream provider cost should be added');
        Assert.isNull(noCost.usage.providerCost, 'No reported cost should leave it to the token rates');

        ApexAgentConfigTypes.AgentConfig rates = ApexAgentTestDataFactory.newAgentConfig('OpenRouter');
        rates.uncachedInputCostPerM = 1;
        rates.cachedInputCostPerM   = 0.1;
        rates.outputCostPerM        = 10;
        noCost.usage.cachedInputTokens = 40;
        Assert.areEqual(0.00042, ApexAgentOrchestratorUtils.callCost(paid.usage, rates),
            'A reported cost should be used as-is');
        Assert.areEqual((60 * 1 + 40 * 0.1 + 20 * 10) / 1000000.0, ApexAgentOrchestratorUtils.callCost(noCost.usage, rates),
            'Without a reported cost, tokens should be priced at the LLM rates');
    }
}
