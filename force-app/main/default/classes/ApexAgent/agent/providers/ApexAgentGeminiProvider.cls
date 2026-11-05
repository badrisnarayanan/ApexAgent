/**
 * Google Gemini through the OpenAI compatibility layer of Google AI Studio
 * (the Gemini API).
 *
 * Thought signatures: Gemini 3 returns a signature on the first tool call of a
 * response, in extra_content.google.thought_signature, and rejects the next
 * request of the same turn if that call comes back without it. Earlier turns
 * may be replayed unsigned. So the signature is kept on the tool call as
 * returned, and when a response has none the documented skip value goes on
 * the first call instead, for the turn in progress only.
 *
 * Usage: completion_tokens leaves reasoning out; it only shows in
 * total_tokens. Output is normalised to include it.
 */
public with sharing class ApexAgentGeminiProvider extends ApexAgentLLMProvider {

    @TestVisible
    private static final String TOKEN_FORMAT = 'google';
    @TestVisible
    private static final String SKIP_SIGNATURE = 'skip_thought_signature_validator';

    /**
     * Returns the signature on the first tool call, tagged for logging. A
     * response without one gets the skip value on that call, which is not logged.
     */
    protected override String readContinuityToken(
        Map<String, Object> message,
        List<ApexAgentApiTypes.ToolCall> toolCalls
    ) {
        if (toolCalls.isEmpty()) {
            return null;
        }
        String signature = asString(googleExtras(toolCalls[0].extra_content)?.get('thought_signature'));
        if (String.isBlank(signature)) {
            setSignature(toolCalls[0], SKIP_SIGNATURE);
            return null;
        }
        return encodeToken(TOKEN_FORMAT, signature);
    }

    public override void attachContinuity(ApexAgentApiTypes.ChatMessage assistantTurn, String storedToken) {
        String signature = decodeToken(TOKEN_FORMAT, storedToken);
        if (signature == null || assistantTurn.tool_calls == null || assistantTurn.tool_calls.isEmpty()) {
            return;
        }
        setSignature(assistantTurn.tool_calls[0], signature);
    }

    protected override ApexAgentLLMTypes.LLMUsage parseUsage(Map<String, Object> usage) {
        ApexAgentLLMTypes.LLMUsage result = super.parseUsage(usage);
        Integer unreported = result.totalTokens - result.inputTokens - result.outputTokens;
        if (result.reasoningTokens == 0 && unreported > 0) {
            result.reasoningTokens = unreported;
            result.outputTokens += unreported;
        }
        return result;
    }

    private static Map<String, Object> googleExtras(Map<String, Object> extraContent) {
        return asMap(extraContent?.get('google'));
    }

    private static void setSignature(ApexAgentApiTypes.ToolCall call, String signature) {
        if (call.extra_content == null) {
            call.extra_content = new Map<String, Object>();
        }
        Map<String, Object> google = googleExtras(call.extra_content);
        if (google == null) {
            google = new Map<String, Object>();
            call.extra_content.put('google', google);
        }
        google.put('thought_signature', signature);
    }
}
