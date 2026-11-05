/**
 * Provider-neutral result types. Every adapter parses its provider's response
 * into these, so the orchestrator never reads a provider-specific field.
 */
public with sharing class ApexAgentLLMTypes {

    /** One chat completion, parsed. */
    public class LLMResult {
        public String content;
        /** stop / tool_calls / length / content_filter, as the provider reported it. */
        public String finishReason;
        /** Tool calls as returned, including any provider extras the adapter must send back. */
        public List<ApexAgentApiTypes.ToolCall> toolCalls = new List<ApexAgentApiTypes.ToolCall>();
        /** Human-readable reasoning, when the provider returns any. */
        public String thought;
        /**
         * The value the provider needs back to continue its reasoning, tagged with
         * the adapter's format (see ApexAgentLLMProvider.encodeToken). Logged as-is.
         */
        public String continuityToken;
        public LLMUsage usage = new LLMUsage();

        public Boolean hasToolCalls() {
            return !toolCalls.isEmpty();
        }
    }

    /** Token counts for one call, normalised so every provider means the same thing. */
    public class LLMUsage {
        /** All prompt tokens, cached ones included. */
        public Integer inputTokens = 0;
        public Integer cachedInputTokens = 0;
        /** Tokens written to the provider's prompt cache, where it reports them. */
        public Integer cacheWriteTokens = 0;
        /** Billable output, reasoning included. */
        public Integer outputTokens = 0;
        /** The reasoning part of outputTokens. */
        public Integer reasoningTokens = 0;
        public Integer totalTokens = 0;
        /** Cost the provider reported for this call, or null when it reports none. */
        public Decimal providerCost;
    }
}
