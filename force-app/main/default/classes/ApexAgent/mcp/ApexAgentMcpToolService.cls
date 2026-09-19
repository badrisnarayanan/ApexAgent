/**
 * The tool-facing half of the MCP endpoint: which tools a server exposes,
 * how they're listed, and how a call is executed and logged. Everything runs
 * as the real authenticated caller (WITH USER_MODE), so it must only be
 * reached from the authenticated branch - never from the Guest branch.
 */
public with sharing class ApexAgentMcpToolService {

    /** The requested tool doesn't exist or isn't mapped to this MCP server. */
    public class UnknownToolException extends Exception {}

    /**
     * Lists every tool mapped to this MCP server with a valid precomputed
     * schema, reusing the same OpenAI-shaped definitions the agent loop
     * sends the LLM (ApexAgentToolSchemaBuilder) and remapping `parameters`
     * to MCP's `inputSchema`. Each tool carries a readOnlyHint annotation
     * (https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)
     * derived from Modifies_Salesforce_Data__c, so a client can tell which
     * tools are safe to call without confirmation.
     */
    public static Map<String, Object> listTools(Id mcpServerId) {
        Map<String, ApexAgent_Tool__c> toolsByName = queryToolsByName(mcpServerId);
        List<Map<String, Object>> openAiDefs = ApexAgentToolSchemaBuilder.buildToolDefinitionsFromSchema(
            toolsByName, false
        );

        List<Object> tools = new List<Object>();
        for (Map<String, Object> def : openAiDefs) {
            Map<String, Object> fn = (Map<String, Object>) def.get('function');
            ApexAgent_Tool__c tool = toolsByName.get((String) fn.get('name'));
            Boolean isReadOnly = tool == null || tool.Modifies_Salesforce_Data__c != true;

            tools.add(new Map<String, Object>{
                'name' => fn.get('name'),
                'description' => fn.get('description'),
                'inputSchema' => fn.get('parameters'),
                'annotations' => new Map<String, Object>{
                    'readOnlyHint' => isReadOnly
                }
            });
        }

        return new Map<String, Object>{
            'resultType' => 'complete',
            'tools' => tools,
            // Inspector's client-side validation requires ttlMs as a number
            // even though the spec prose doesn't flag it as strictly
            // required - 5 minutes, matching the spec's own example value.
            'ttlMs' => 300000,
            'cacheScope' => 'private'
        };
    }

    /**
     * Executes a tool via the same ApexAgentToolExecutor path the agent loop
     * uses, with the caller's own permissions, sharing, and FLS. A tool that
     * doesn't exist or isn't mapped to this server is a protocol error
     * (UnknownToolException), not a tool-execution error, per the MCP spec's
     * distinction between the two.
     *
     * Always executes inline (forceInline=true), never through the DML
     * bridge: the bridge exists so the agentic loop can still make its next
     * LLM callout after a DML tool runs in the same transaction. A tools/call
     * request is a single synchronous REST response with no further callout
     * afterwards, so that isolation isn't needed here.
     *
     * @param argumentsValue the already-validated `arguments` object, or null
     */
    public static Map<String, Object> callTool(Id mcpServerId, Object requestId, String toolName, Object argumentsValue) {
        Map<String, ApexAgent_Tool__c> toolsByName = queryToolsByName(mcpServerId);
        if (!toolsByName.containsKey(toolName)) {
            throw new UnknownToolException('Unknown tool: ' + toolName);
        }

        ApexAgentApiTypes.ToolCall toolCall = new ApexAgentApiTypes.ToolCall();
        toolCall.id = 'mcp-' + String.valueOf(requestId);
        toolCall.type = 'function';
        toolCall.function = new ApexAgentApiTypes.ToolCallFunction();
        toolCall.function.name = toolName;
        toolCall.function.arguments = JSON.serialize(
            argumentsValue == null ? new Map<String, Object>() : argumentsValue
        );

        Datetime startedAt = Datetime.now();
        ApexAgentExecTypes.ToolResult toolResult = ApexAgentToolExecutor.execute(toolsByName, toolCall, true);
        Datetime endedAt = Datetime.now();
        Boolean isError = toolResult.isError();

        logToolCall(mcpServerId, toolResult, startedAt, endedAt);

        return new Map<String, Object>{
            'resultType' => 'complete',
            'content' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'text',
                    'text' => isError ? toolResult.errorMessage : toolResult.output
                }
            },
            'isError' => isError
        };
    }

    /**
     * Every tool actively mapped to this MCP server via ApexAgent_MCP_Tool_Map__c
     * with a generated schema, keyed by Apex_Class_Name__c - the same key
     * ApexAgentToolExecutor and ApexAgentToolSchemaBuilder both expect.
     * WITH USER_MODE enforces the real caller's sharing and FLS, consistent
     * with how ApexAgentTopicLoader queries tools for the Agentforce path.
     */
    public static Map<String, ApexAgent_Tool__c> queryToolsByName(Id mcpServerId) {
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>();
        for (ApexAgent_MCP_Tool_Map__c mapping : [
            SELECT Tool__r.Apex_Class_Name__c, Tool__r.Modifies_Salesforce_Data__c, Tool__r.Schema__c
            FROM ApexAgent_MCP_Tool_Map__c
            WHERE MCP__c = :mcpServerId AND Active__c = true
            WITH USER_MODE
        ]) {
            // Schema__c is a Long Text Area - it cannot be filtered in the
            // query itself (platform restriction), so blank schemas are
            // skipped here instead. ApexAgentToolSchemaBuilder also skips
            // blank/invalid schemas independently, so this is belt-and-
            // suspenders, not the only place it's handled.
            if (String.isBlank(mapping.Tool__r.Schema__c)) {
                continue;
            }
            toolsByName.put(mapping.Tool__r.Apex_Class_Name__c, mapping.Tool__r);
        }
        return toolsByName;
    }

    /**
     * Logs an MCP-originated tool call to Tool_Log__c via the same
     * ApexAgentLogger the Agentforce path uses, with MCP__c set instead of
     * Message_Log__c. Status is normalized to the same Success/Error
     * capitalization the Agentforce path already writes, so Status__c stays
     * consistent for reporting regardless of origin.
     */
    private static void logToolCall(Id mcpServerId, ApexAgentExecTypes.ToolResult toolResult, Datetime startedAt, Datetime endedAt) {
        ApexAgentLogger.ToolLogEntry entry = new ApexAgentLogger.ToolLogEntry();
        entry.toolCallId = toolResult.toolId;
        entry.toolName = toolResult.name;
        entry.inputJson = toolResult.inputArguments;
        entry.outputJson = toolResult.output;
        entry.status = ApexAgentLogger.toolLogStatus(toolResult);
        entry.errorMessage = toolResult.errorMessage;
        entry.stackTrace = toolResult.errorStackTrace;
        entry.startedAt = startedAt;
        entry.endedAt = endedAt;
        ApexAgentLogger.logMcpToolCall(mcpServerId, entry);
    }
}
