/**
 * Utility helpers for the ApexAgent orchestration layer.
 * Extracted from ApexAgentOrchestrator to keep that class focused on loop coordination.
 */
public with sharing class ApexAgentOrchestratorUtils {

    /**
     * Builds the assistant turn that carries this response's tool calls back to
     * the provider, with the provider's continuity token attached.
     */
    public static ApexAgentApiTypes.ChatMessage buildAssistantTurn(
        ApexAgentLLMTypes.LLMResult result,
        ApexAgentLLMProvider provider
    ) {
        ApexAgentApiTypes.ChatMessage turn = new ApexAgentApiTypes.ChatMessage();
        turn.role       = 'assistant';
        turn.tool_calls = result.toolCalls;
        provider.attachContinuity(turn, result.continuityToken);
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
        entry.status            = ApexAgentLogger.toolLogStatus(result);
        entry.errorMessage      = result.errorMessage;
        entry.stackTrace        = result.errorStackTrace;
        entry.thoughtSignature  = signature;
        entry.executionMessage  = executionMessage;
        entry.startedAt         = toolStart;
        entry.endedAt           = toolEnd;
        return entry;
    }

    /**
     * The cost of one LLM call: what the provider reported when it reports a
     * cost, otherwise the tokens priced at the LLM record's per-million rates.
     */
    public static Decimal callCost(ApexAgentLLMTypes.LLMUsage usage, ApexAgentConfigTypes.AgentConfig cfg) {
        if (usage.providerCost != null) {
            return usage.providerCost;
        }
        Decimal cost     = 0;
        Integer uncached = usage.inputTokens - usage.cachedInputTokens;
        if (cfg.uncachedInputCostPerM != null && uncached > 0) {
            cost += (Decimal) uncached * cfg.uncachedInputCostPerM / 1000000;
        }
        if (cfg.cachedInputCostPerM != null && usage.cachedInputTokens > 0) {
            cost += (Decimal) usage.cachedInputTokens * cfg.cachedInputCostPerM / 1000000;
        }
        if (cfg.outputCostPerM != null && usage.outputTokens > 0) {
            cost += (Decimal) usage.outputTokens * cfg.outputCostPerM / 1000000;
        }
        return cost;
    }
}
