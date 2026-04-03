/**
 * Unified tool execution layer for the ApexAgent framework.
 *
 * Routes an LLM tool call to either an Apex class or a Flow, resolving the
 * tool record from a pre-built name map.  Tools that modify Salesforce data
 * are automatically dispatched through an internal REST callout so that
 * subsequent LLM API callouts remain valid (no DML-before-callout error).
 */
public with sharing class ApexAgentToolExecutor {

    /**
     * Executes the tool identified in the given tool call.
     *
     * @param toolsByName  Map of Tool_API_Name__c → ApexAgent_Tool__c record
     * @param toolCall     Typed wrapper for the OpenAI tool call object
     * @return             ToolResult populated with execution metadata and outcome
     */
    public static ApexAgentExecTypes.ToolResult execute(
        Map<String, ApexAgent_Tool__c> toolsByName,
        ApexAgentApiTypes.ToolCall toolCall
    ) {
        ApexAgentExecTypes.ToolResult result = new ApexAgentExecTypes.ToolResult();
        result.toolId = toolCall.id;
        result.name = toolCall.function.name;
        result.inputArguments = toolCall.function.arguments;

        try {
            ApexAgent_Tool__c tool = toolsByName.get(toolCall.function.name);
            if (tool == null) {
                throw new IllegalArgumentException('No tool registered with name: ' + toolCall.function.name);
            }

            result.type = tool.Execution_Type__c;
            result.implementation = tool.Execution_Name__c;

            Map<String, Object> inputs = (Map<String, Object>) JSON.deserializeUntyped(
                toolCall.function.arguments
            );

            result.output = tool.Modifies_Salesforce_Data__c
                ? executeViaDmlBridge(tool, inputs)
                : executeInline(tool.Execution_Type__c, tool.Execution_Name__c, inputs);

            result.status = 'success';

        } catch (ApexAgentDmlBridgeResource.BridgeException e) {
            result.status = 'error';
            result.errorMessage = e.getMessage();
            result.errorStackTrace = e.originalStackTrace;
        } catch (Exception e) {
            result.status = 'error';
            result.errorMessage = e.getMessage();
            result.errorStackTrace = e.getStackTraceString();
        }

        return result;
    }

    // ─── Inline execution (non-DML tools) ────────────────────────────────────

    /**
     * Executes a tool in the current transaction context.
     * Called for non-DML tools and from the DML bridge REST resource.
     *
     * @param executionType  'Apex' or 'Flow'
     * @param executionName  Apex class name or Flow API name
     * @param inputs         Parsed function arguments from the LLM tool call
     * @return               JSON-serialized tool result
     */
    public static String executeInline(
        String executionType,
        String executionName,
        Map<String, Object> inputs
    ) {
        if (executionType == 'Apex') {
            Type t = Type.forName(executionName);
            if (t == null) {
                throw new IllegalArgumentException('Apex tool class not found: ' + executionName);
            }
            ApexAgentTool toolInstance = (ApexAgentTool) t.newInstance();
            return JSON.serialize(toolInstance.execute(inputs));
        }

        if (executionType == 'Flow') {
            Flow.Interview interview = Flow.Interview.createInterview(executionName, inputs);
            interview.start();
            return String.valueOf(interview);
        }

        throw new IllegalArgumentException('Unknown execution type: ' + executionType);
    }

    // ─── DML bridge (data-modifying tools) ───────────────────────────────────

    // Session ID from the VF page is required here — named credentials cannot be used
    // for same-org callouts where the session must belong to the running user.
    @SuppressWarnings('PMD.ApexSuggestUsingNamedCredential')
    private static String executeViaDmlBridge(
        ApexAgent_Tool__c tool,
        Map<String, Object> inputs
    ) {
        String sessionId = Page.ApexAgentSession.getContent().toString().trim();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/apexrest/ApexAgent/dml-bridge');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + sessionId); //NOPMD - session ID from VF page required for same-org callout
        req.setBody(JSON.serialize(new Map<String, Object>{
            'executionType' => tool.Execution_Type__c,
            'executionName' => tool.Execution_Name__c,
            'inputs'        => inputs
        }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            Map<String, Object> bridgeError = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String originalMessage    = (String) bridgeError.get('error');
            String originalStackTrace = (String) bridgeError.get('stackTrace');
            throw new ApexAgentDmlBridgeResource.BridgeException(originalMessage, originalStackTrace);
        }
        return res.getBody();
    }
}
