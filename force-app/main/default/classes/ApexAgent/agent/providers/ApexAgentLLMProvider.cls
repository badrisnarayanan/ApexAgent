/**
 * Base class for an LLM provider adapter. Every provider speaks OpenAI chat
 * completions; an adapter overrides only the parts where its provider differs.
 * The defaults here are plain OpenAI.
 *
 * To add a provider, extend this class, override the hooks you need, give the
 * class a public no-argument constructor, and create an
 * ApexAgent_Model_Provider__c record with type Custom and your class name in
 * Apex Class. ApexAgentLLMProviderFactory creates it for you.
 *
 * Hooks, in the order a call uses them:
 *   buildRequestBody / mapReasoningEffort  the JSON body sent to the provider
 *   retryBodyAfterRejection                one corrected resend after a rejected request
 *   isRetryable                            which failures are worth sending again
 *   parseResponse / parseUsage             the response, as neutral ApexAgentLLMTypes
 *   readThought / readContinuityToken      reasoning text and the token to send back
 *   attachContinuity                       puts that token back on an assistant turn
 */
public abstract with sharing class ApexAgentLLMProvider {

    /** Thrown for a misconfigured provider or a response the adapter can't use. */
    public class ProviderException extends Exception {}

    protected ApexAgentConfigTypes.AgentConfig config;
    private final List<String> warnings = new List<String>();

    /** Called once by the factory, before any other method. */
    public void setConfig(ApexAgentConfigTypes.AgentConfig config) {
        this.config = config;
    }

    /** Problems an admin should fix, collected during the turn and logged at its end. */
    public List<String> getWarnings() {
        return warnings;
    }

    protected void addWarning(String message) {
        warnings.add(message);
    }

    // ─────────────────────────────────────────────────────────────────
    // Request
    // ─────────────────────────────────────────────────────────────────

    /** The callout URL. The named credential holds the base URL; the path is appended as-is. */
    public virtual String endpoint() {
        return 'callout:' + config.namedCredential + (config.chatCompletionsPath ?? '');
    }

    public virtual Map<String, Object> buildRequestBody(
        List<Object> messages,
        List<Map<String, Object>> toolDefs
    ) {
        Map<String, Object> body = new Map<String, Object>{
            'model'                 => config.modelApiName,
            'messages'              => messages,
            'max_completion_tokens' => config.maxTokens,
            'stream'                => false
        };
        if (toolDefs != null && !toolDefs.isEmpty()) {
            body.put('tools', toolDefs);
            body.put('tool_choice', 'auto');
        }
        String effort = mapReasoningEffort();
        if (String.isNotBlank(effort)) {
            body.put('reasoning_effort', effort);
        }
        return body;
    }

    /**
     * The reasoning_effort value to send, or null to leave the field out.
     * By default it is sent only when the LLM supports reasoning and the agent
     * sets an effort other than "disabled".
     */
    protected virtual String mapReasoningEffort() {
        if (config.supportsReasoning != true
                || String.isBlank(config.reasoningEffort)
                || config.reasoningEffort == 'disabled') {
            return null;
        }
        return config.reasoningEffort;
    }

    /**
     * A corrected request body to send once more after the provider rejected
     * the request, or null to treat the rejection as a failure. The client
     * resends at most once per call.
     */
    public virtual Map<String, Object> retryBodyAfterRejection(
        Integer statusCode,
        String responseBody,
        Map<String, Object> requestBody
    ) {
        return null;
    }

    /**
     * Whether a failed call is worth sending again unchanged: rate limits and
     * server errors. A 429 for an exhausted balance won't clear by retrying.
     */
    public virtual Boolean isRetryable(Integer statusCode, String responseBody) {
        if (statusCode == 429) {
            return responseBody == null || !responseBody.contains('insufficient_quota');
        }
        return statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504;
    }

    // ─────────────────────────────────────────────────────────────────
    // Response
    // ─────────────────────────────────────────────────────────────────

    public virtual ApexAgentLLMTypes.LLMResult parseResponse(String responseBody) {
        Map<String, Object> root = asMap(JSON.deserializeUntyped(responseBody));
        List<Object> choices = asList(root?.get('choices'));
        if (choices == null || choices.isEmpty()) {
            Object error = root?.get('error');
            throw new ProviderException('LLM response contained no choices.'
                + (error != null ? ' Error: ' + JSON.serialize(error) : ''));
        }
        Map<String, Object> choice = asMap(choices[0]);
        if (choice == null) {
            throw new ProviderException('LLM response choice was not an object: ' + JSON.serialize(choices[0])
                + (root.get('error') != null ? ' Error: ' + JSON.serialize(root.get('error')) : ''));
        }
        Map<String, Object> message = asMap(choice.get('message')) ?? new Map<String, Object>();

        ApexAgentLLMTypes.LLMResult result = new ApexAgentLLMTypes.LLMResult();
        result.content      = asString(message.get('content'));
        result.finishReason = asString(choice.get('finish_reason'));
        for (Object item : asList(message.get('tool_calls')) ?? new List<Object>()) {
            result.toolCalls.add(parseToolCall(asMap(item)));
        }
        result.thought         = readThought(message);
        result.continuityToken = readContinuityToken(message, result.toolCalls);
        result.usage           = parseUsage(asMap(root.get('usage')));
        return result;
    }

    /** Reasoning text from the response message. OpenAI chat completions returns none. */
    protected virtual String readThought(Map<String, Object> message) {
        return null;
    }

    /** The provider's continuity token, tagged with encodeToken. OpenAI needs none. */
    protected virtual String readContinuityToken(
        Map<String, Object> message,
        List<ApexAgentApiTypes.ToolCall> toolCalls
    ) {
        return null;
    }

    /** OpenAI usage: completion_tokens already includes reasoning. */
    protected virtual ApexAgentLLMTypes.LLMUsage parseUsage(Map<String, Object> usage) {
        ApexAgentLLMTypes.LLMUsage result = new ApexAgentLLMTypes.LLMUsage();
        if (usage == null) {
            return result;
        }
        Map<String, Object> promptDetails = asMap(usage.get('prompt_tokens_details'));
        Map<String, Object> completionDetails = asMap(usage.get('completion_tokens_details'));
        result.inputTokens       = asInteger(usage.get('prompt_tokens'));
        result.outputTokens      = asInteger(usage.get('completion_tokens'));
        result.cachedInputTokens = asInteger(promptDetails?.get('cached_tokens'));
        result.cacheWriteTokens  = asInteger(promptDetails?.get('cache_write_tokens'));
        result.reasoningTokens   = asInteger(completionDetails?.get('reasoning_tokens'));
        result.totalTokens       = usage.containsKey('total_tokens')
            ? asInteger(usage.get('total_tokens'))
            : result.inputTokens + result.outputTokens;
        return result;
    }

    // ─────────────────────────────────────────────────────────────────
    // Continuity
    // ─────────────────────────────────────────────────────────────────

    /**
     * Puts a stored continuity token back on an assistant turn that carries tool
     * calls, for the turn in progress and for replayed history. A token written
     * by a different adapter must be ignored: decodeToken returns null for it.
     */
    public virtual void attachContinuity(ApexAgentApiTypes.ChatMessage assistantTurn, String storedToken) {
        return;
    }

    /** Tags a raw token with its format, so another adapter can tell it isn't its own. */
    protected String encodeToken(String format, String rawToken) {
        return String.isBlank(rawToken) ? null : format + ':' + rawToken;
    }

    /** The raw token when storedToken was written in this format, otherwise null. */
    protected String decodeToken(String format, String storedToken) {
        String prefix = format + ':';
        return storedToken != null && storedToken.startsWith(prefix)
            ? storedToken.substring(prefix.length())
            : null;
    }

    // ─────────────────────────────────────────────────────────────────
    // Untyped JSON helpers (public: Apex has no protected static)
    // ─────────────────────────────────────────────────────────────────

    protected ApexAgentApiTypes.ToolCall parseToolCall(Map<String, Object> raw) {
        ApexAgentApiTypes.ToolCall call = new ApexAgentApiTypes.ToolCall();
        call.id   = asString(raw.get('id'));
        call.type = asString(raw.get('type')) ?? 'function';
        Map<String, Object> fn = asMap(raw.get('function'));
        if (fn != null) {
            call.function = new ApexAgentApiTypes.ToolCallFunction();
            call.function.name      = asString(fn.get('name'));
            call.function.arguments = asString(fn.get('arguments'));
        }
        call.extra_content = asMap(raw.get('extra_content'));
        return call;
    }

    public static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    public static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }

    public static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    /** JSON numbers arrive as Integer, Long or Decimal. Missing counts as 0. */
    public static Integer asInteger(Object value) {
        Decimal amount = asDecimal(value);
        return amount == null ? 0 : amount.intValue();
    }

    public static Decimal asDecimal(Object value) {
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            return (Long) value;
        }
        return null;
    }
}
