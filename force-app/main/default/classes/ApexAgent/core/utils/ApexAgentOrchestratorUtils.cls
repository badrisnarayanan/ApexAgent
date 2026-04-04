/**
 * Utility helpers for the ApexAgent orchestration layer.
 * Extracted from ApexAgentOrchestrator to keep that class focused on loop coordination.
 */
public with sharing class ApexAgentOrchestratorUtils {

    public static final String REASONING_SUMMARY   = 'reasoning.summary';
    public static final String REASONING_ENCRYPTED = 'reasoning.encrypted';
    public static final String STATUS_ERROR        = 'Error';
    public static final String STATUS_SUCCESS      = 'Success';

    /** Extracts the human-readable thought content from an LLM response message. */
    public static String extractThoughtContent(ApexAgentApiTypes.ResponseMessage msg) {
        if (String.isNotBlank(msg.reasoning)) {
            return msg.reasoning;
        }
        if (msg.reasoning_details != null) {
            for (ApexAgentApiTypes.ReasoningDetail d : msg.reasoning_details) {
                if (REASONING_SUMMARY.equals(d.type) && String.isNotBlank(d.summary)) {
                    return d.summary;
                }
            }
        }
        return null;
    }

    /** Extracts the encrypted thought signature from an LLM response message. */
    public static String extractThoughtSignature(ApexAgentApiTypes.ResponseMessage msg) {
        if (msg.reasoning_details == null) {
            return null;
        }
        for (ApexAgentApiTypes.ReasoningDetail d : msg.reasoning_details) {
            if (REASONING_ENCRYPTED.equals(d.type) && String.isNotBlank(d.data)) {
                return d.data;
            }
        }
        return null;
    }

    /**
     * Builds the assistant ChatMessage turn that carries tool_calls and,
     * optionally, the encrypted reasoning signature for continuity.
     */
    public static ApexAgentApiTypes.ChatMessage buildAssistantTurn(
        ApexAgentApiTypes.ResponseMessage msg,
        String signature
    ) {
        ApexAgentApiTypes.ChatMessage turn = new ApexAgentApiTypes.ChatMessage();
        turn.role       = 'assistant';
        turn.tool_calls = msg.tool_calls;

        if (String.isNotBlank(signature)) {
            ApexAgentApiTypes.ReasoningDetail rd = new ApexAgentApiTypes.ReasoningDetail();
            rd.type = REASONING_ENCRYPTED;
            rd.data = signature;
            turn.reasoning_details = new List<ApexAgentApiTypes.ReasoningDetail>{ rd };
        }
        return turn;
    }

    /**
     * Extracts and strips the execution_message key from the tool call's JSON arguments.
     * Modifies tc.function.arguments in place (removes the key so the tool never sees it).
     * Returns the extracted message, or an empty string if absent.
     */
    public static String extractAndStripExecutionMessage(ApexAgentApiTypes.ToolCall tc) {
        if (tc.function == null || String.isBlank(tc.function.arguments)) {
            return '';
        }
        Map<String, Object> args = (Map<String, Object>) JSON.deserializeUntyped(tc.function.arguments);
        Object msg = args.remove('execution_message');
        tc.function.arguments = JSON.serialize(args);
        return msg != null ? String.valueOf(msg) : '';
    }

    /** Builds a ToolLogEntry from a completed tool call and its result. */
    public static ApexAgentLogger.ToolLogEntry buildToolLogEntry(
        ApexAgentApiTypes.ToolCall tc,
        ApexAgentExecTypes.ToolResult result,
        Datetime toolStart,
        Datetime toolEnd,
        String signature,
        String executionMessage
    ) {
        ApexAgentLogger.ToolLogEntry entry = new ApexAgentLogger.ToolLogEntry();
        entry.toolCallId        = tc.id;
        entry.toolName          = tc.function != null ? tc.function.name      : null;
        entry.inputJson         = tc.function != null ? tc.function.arguments : null;
        entry.outputJson        = result.output;
        entry.status            = STATUS_ERROR.equals(result.status) ? STATUS_ERROR : STATUS_SUCCESS;
        entry.errorMessage      = result.errorMessage;
        entry.stackTrace        = result.errorStackTrace;
        entry.thoughtSignature  = signature;
        entry.executionMessage  = executionMessage;
        entry.startedAt         = toolStart;
        entry.endedAt           = toolEnd;
        return entry;
    }

    /** Calculates the estimated cost of an LLM call from token counts and per-million rates. */
    public static Decimal calculateCost(
        Integer promptTokens,
        Integer completionTokens,
        Integer cachedTokens,
        ApexAgentConfigTypes.AgentConfig cfg
    ) {
        Decimal cost     = 0;
        Integer uncached = (promptTokens != null ? promptTokens : 0)
                         - (cachedTokens != null ? cachedTokens : 0);
        if (cfg.uncachedInputCostPerM != null && uncached > 0) {
            cost += (Decimal) uncached * cfg.uncachedInputCostPerM / 1000000;
        }
        if (cfg.cachedInputCostPerM != null && cachedTokens != null && cachedTokens > 0) {
            cost += (Decimal) cachedTokens * cfg.cachedInputCostPerM / 1000000;
        }
        if (cfg.outputCostPerM != null && completionTokens != null && completionTokens > 0) {
            cost += (Decimal) completionTokens * cfg.outputCostPerM / 1000000;
        }
        return cost;
    }
}
