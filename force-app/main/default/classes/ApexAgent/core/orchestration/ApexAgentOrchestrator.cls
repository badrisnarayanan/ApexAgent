/**
 * Entry point for the ApexAgent agentic loop.
 * Coordinates config loading, message building, LLM calls, tool execution,
 * and logging for a single user message turn.
 */
public with sharing class ApexAgentOrchestrator {

    private static final Integer MAX_TOOL_ITERATIONS = 10;
    private static final String  FINISH_TOOL_CALLS   = 'tool_calls';

    // ─────────────────────────────────────────────────────────────────
    // Public return type
    // ─────────────────────────────────────────────────────────────────

    public class AgentResponse {
        public String llmResponse;
        public String errorMessage;
        public String messageUUID;
    }

    // ─────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────

    public static AgentResponse run(
        String threadUUID,
        String userMessage,
        String systemContext,
        String agentName,
        String messageUUID
    ) {
        String resolvedUUID = String.isNotBlank(messageUUID)
            ? messageUUID
            : UUID.randomUUID().toString();

        AgentResponse response = new AgentResponse();
        response.messageUUID = resolvedUUID;

        Datetime startedAt = Datetime.now();
        String   lastContent = null;
        String   errorMsg    = null;

        // Token accumulators across all loop iterations
        Integer accumPrompt     = 0;
        Integer accumCompletion = 0;
        Integer accumCached     = 0;
        Integer accumReasoning  = 0;
        Integer accumTotal      = 0;

        List<ApexAgentLogger.ToolLogEntry> toolEntries = new List<ApexAgentLogger.ToolLogEntry>();
        String lastSignature = null;
        String lastThought   = null;

        // Declared outside try so the logging block can access it without a second query
        ApexAgentConfigTypes.AgentConfig config = null;

        try {
            // ── 1. Load agent config, topics, tools ──────────────────
            ApexAgentConfigTypes.LoadResult loaded = ApexAgentTopicLoader.load(agentName);
            config = loaded.config;
            List<Map<String, Object>> toolDefs =
                ApexAgentTopicLoader.buildToolDefinitions(loaded.toolsByName);

            // ── 2. Build messages array ───────────────────────────────
            List<Object> messages = new List<Object>();
            messages.add(ApexAgentMessageBuilder.buildSystemMessage(config, loaded.topics));

            if (String.isNotBlank(threadUUID) && config.conversationDepth > 0) {
                messages.addAll(ApexAgentMessageBuilder.buildThreadHistory(
                    threadUUID,
                    config.conversationDepth,
                    config.toolLogDepth,
                    config.modelFamily
                ));
            }

            messages.add(ApexAgentMessageBuilder.buildUserMessage(userMessage));
            messages.add(ApexAgentMessageBuilder.buildContextMessage(systemContext));

            // ── 3. Agentic loop ───────────────────────────────────────
            Integer iteration = 0;
            while (iteration <= MAX_TOOL_ITERATIONS) {

                if (iteration == MAX_TOOL_ITERATIONS) {
                    ApexAgentApiTypes.ChatMessage nudge = new ApexAgentApiTypes.ChatMessage();
                    nudge.role    = 'user';
                    nudge.content = 'You have reached the maximum tool call iterations. '
                        + 'Provide your final answer now without any further tool calls, '
                        + 'based on what you have gathered so far.';
                    messages.add(nudge);
                }

                List<Map<String, Object>> currentTools = iteration < MAX_TOOL_ITERATIONS
                    ? toolDefs
                    : new List<Map<String, Object>>();

                ApexAgentApiTypes.ChatCompletionResponse resp =
                    ApexAgentLLMClient.call(config, messages, currentTools);

                if (resp.usage != null) {
                    accumPrompt     += resp.usage.prompt_tokens     != null ? resp.usage.prompt_tokens     : 0;
                    accumCompletion += resp.usage.completion_tokens  != null ? resp.usage.completion_tokens  : 0;
                    accumTotal      += resp.usage.total_tokens       != null ? resp.usage.total_tokens       : 0;
                    if (resp.usage.prompt_tokens_details != null) {
                        accumCached += resp.usage.prompt_tokens_details.cached_tokens != null
                            ? resp.usage.prompt_tokens_details.cached_tokens : 0;
                    }
                    if (resp.usage.completion_tokens_details != null) {
                        accumReasoning += resp.usage.completion_tokens_details.reasoning_tokens != null
                            ? resp.usage.completion_tokens_details.reasoning_tokens : 0;
                    }
                }

                ApexAgentApiTypes.ResponseMessage assistantMsg = resp.choices[0].message;
                lastThought   = ApexAgentOrchestratorUtils.extractThoughtContent(assistantMsg);
                lastSignature = ApexAgentOrchestratorUtils.extractThoughtSignature(assistantMsg);

                String finishReason = resp.choices[0].finish_reason;

                if (FINISH_TOOL_CALLS.equals(finishReason)
                        && assistantMsg.tool_calls != null
                        && !assistantMsg.tool_calls.isEmpty()
                        && iteration < MAX_TOOL_ITERATIONS) {

                    messages.add(ApexAgentOrchestratorUtils.buildAssistantTurn(assistantMsg, lastSignature));

                    for (ApexAgentApiTypes.ToolCall tc : assistantMsg.tool_calls) {
                        Datetime toolStart = Datetime.now();
                        ApexAgentExecTypes.ToolResult result =
                            ApexAgentToolExecutor.execute(loaded.toolsByName, tc);
                        Datetime toolEnd = Datetime.now();

                        ApexAgentApiTypes.ChatMessage toolMsg = new ApexAgentApiTypes.ChatMessage();
                        toolMsg.role         = 'tool';
                        toolMsg.tool_call_id = tc.id;
                        toolMsg.content      = ApexAgentOrchestratorUtils.STATUS_ERROR.equals(result.status)
                            ? result.errorMessage
                            : result.output;
                        messages.add(toolMsg);

                        toolEntries.add(
                            ApexAgentOrchestratorUtils.buildToolLogEntry(tc, result, toolStart, toolEnd, lastSignature)
                        );
                    }

                    // Both vars have been attached to the assistant turn and stored in each
                    // ToolLogEntry for this round. Reset so round N's signature doesn't bleed
                    // into round N+1's tool logs — the next LLM response will repopulate them.
                    lastSignature = null;
                    lastThought   = null;
                    iteration++;

                } else {
                    lastContent = assistantMsg.content;
                    break;
                }
            }

        } catch (Exception e) {
            errorMsg = e.getMessage() + '\n' + e.getStackTraceString();
        }

        // ── 4. Log everything ─────────────────────────────────────
        Datetime endedAt = Datetime.now();
        try {
            String logThreadUUID = String.isNotBlank(threadUUID) ? threadUUID : resolvedUUID;

            ApexAgentLogger.LogPayload payload = new ApexAgentLogger.LogPayload();
            payload.threadUUID       = logThreadUUID;
            payload.messageUUID      = resolvedUUID;
            payload.agentId          = config != null ? config.agentId       : null;
            payload.agentName        = agentName;
            payload.modelName        = config != null ? config.modelApiName  : null;
            payload.userInput        = userMessage;
            payload.agentResponse    = lastContent;
            payload.thoughtContent   = lastThought;
            payload.thoughtSignature = lastSignature;
            payload.startedAt        = startedAt;
            payload.endedAt          = endedAt;
            payload.promptTokens     = accumPrompt;
            payload.completionTokens = accumCompletion;
            payload.cachedTokens     = accumCached;
            payload.reasoningTokens  = accumReasoning;
            payload.totalTokens      = accumTotal;
            payload.cost             = config != null
                ? ApexAgentOrchestratorUtils.calculateCost(accumPrompt, accumCompletion, accumCached, config)
                : null;
            payload.toolLogs         = toolEntries;
            payload.errorMessage     = errorMsg;
            payload.errorStackTrace  = null; // already embedded in errorMsg above

            ApexAgentLogger.insertLogs(payload);
        } catch (Exception logEx) {
            System.debug(LoggingLevel.WARN,
                'ApexAgentOrchestrator: logging failed for message ' + resolvedUUID
                + ': ' + logEx.getMessage()
            );
        }

        response.llmResponse  = lastContent;
        response.errorMessage = errorMsg;
        return response;
    }

}
