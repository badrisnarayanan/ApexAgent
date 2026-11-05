/**
 * OpenRouter: OpenAI chat completions plus reasoning text, encrypted reasoning
 * in reasoning_details[], and the cost of each call in usage.
 */
public with sharing class ApexAgentOpenRouterProvider extends ApexAgentLLMProvider {

    @TestVisible
    private static final String TOKEN_FORMAT = 'openrouter';
    private static final String REASONING_SUMMARY   = 'reasoning.summary';
    private static final String REASONING_ENCRYPTED = 'reasoning.encrypted';

    protected override String readThought(Map<String, Object> message) {
        String reasoning = asString(message.get('reasoning'));
        if (String.isNotBlank(reasoning)) {
            return reasoning;
        }
        for (Object item : asList(message.get('reasoning_details')) ?? new List<Object>()) {
            Map<String, Object> detail = asMap(item);
            if (detail?.get('type') == REASONING_SUMMARY && String.isNotBlank(asString(detail.get('summary')))) {
                return asString(detail.get('summary'));
            }
        }
        return null;
    }

    protected override String readContinuityToken(
        Map<String, Object> message,
        List<ApexAgentApiTypes.ToolCall> toolCalls
    ) {
        for (Object item : asList(message.get('reasoning_details')) ?? new List<Object>()) {
            Map<String, Object> detail = asMap(item);
            if (detail?.get('type') == REASONING_ENCRYPTED && String.isNotBlank(asString(detail.get('data')))) {
                return encodeToken(TOKEN_FORMAT, asString(detail.get('data')));
            }
        }
        return null;
    }

    public override void attachContinuity(ApexAgentApiTypes.ChatMessage assistantTurn, String storedToken) {
        String data = decodeToken(TOKEN_FORMAT, storedToken);
        if (data == null) {
            return;
        }
        ApexAgentApiTypes.ReasoningDetail detail = new ApexAgentApiTypes.ReasoningDetail();
        detail.type = REASONING_ENCRYPTED;
        detail.data = data;
        assistantTurn.reasoning_details = new List<ApexAgentApiTypes.ReasoningDetail>{ detail };
    }

    /**
     * usage.cost is what OpenRouter charged. With your own provider key (BYOK)
     * that is only OpenRouter's fee, often 0, and the provider's own charge is
     * in cost_details.upstream_inference_cost, so the two are added.
     */
    protected override ApexAgentLLMTypes.LLMUsage parseUsage(Map<String, Object> usage) {
        ApexAgentLLMTypes.LLMUsage result = super.parseUsage(usage);
        Decimal cost = asDecimal(usage?.get('cost'));
        if (cost != null && usage.get('is_byok') == true) {
            Decimal upstream = asDecimal(asMap(usage.get('cost_details'))?.get('upstream_inference_cost'));
            cost += upstream ?? 0;
        }
        result.providerCost = cost;
        return result;
    }
}
