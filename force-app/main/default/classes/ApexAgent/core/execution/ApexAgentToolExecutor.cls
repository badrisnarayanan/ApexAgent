/**
 * Unified tool execution layer for the ApexAgent framework.
 *
 * Routes an LLM tool call to the tool's Apex Action (@InvocableMethod), resolving
 * the tool record from a pre-built name map. Tools that modify Salesforce data
 * are automatically dispatched through an internal REST callout so that
 * subsequent LLM API callouts remain valid (no DML-before-callout error).
 *
 * Dispatch goes through Invocable.Action rather than a compile-time interface
 * cast: the LLM's raw JSON arguments are matched against the action's own
 * describe() metadata, which supplies required-parameter validation and,
 * critically, the exact Apex type of every list-typed parameter — a raw
 * JSON.deserializeUntyped map's List<Object> does not coerce into a declared
 * List<String>/List<CustomType> field, so each such value is rebuilt as a
 * genuinely-typed Apex list (via Type.forName + JSON.deserialize) before
 * the action is invoked.
 */
public with sharing class ApexAgentToolExecutor {

    private static final Integer DML_BRIDGE_TIMEOUT_MS = 60000;
    private static final String ACTION_TYPE = 'apex';

    /**
     * Executes the tool identified in the given tool call.
     *
     * @param toolsByName Map of Apex_Class_Name__c → ApexAgent_Tool__c record
     * @param toolCall Typed wrapper for the OpenAI tool call object
     * @return ToolResult populated with execution metadata and outcome
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

            result.implementation = tool.Apex_Class_Name__c;

            Map<String, Object> inputs = (Map<String, Object>) JSON.deserializeUntyped(
                toolCall.function.arguments
            );

            result.output = tool.Modifies_Salesforce_Data__c
                ? executeViaDmlBridge(tool, inputs)
                : executeInline(tool.Apex_Class_Name__c, inputs);

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
     * Executes a tool's Apex Action in the current transaction context.
     * Called for non-DML tools and from the DML bridge REST resource.
     *
     * @param executionName Apex class name implementing the @InvocableMethod action
     * @param inputs Parsed function arguments from the LLM tool call
     * @return JSON-serialized tool result
     */
    public static String executeInline(String executionName, Map<String, Object> inputs) {
        Invocable.Action action = Invocable.Action.createCustomAction(ACTION_TYPE, executionName);
        List<Invocable.Action.DescribeResult> describes = action.getDescribe();
        if (describes.isEmpty()) {
            throw new IllegalArgumentException(
                'Apex tool class not found or has no @InvocableMethod: ' + executionName
            );
        }

        Map<String, Object> typedInputs = buildTypedInvocationMap(describes[0].getInputs(), inputs);
        action.setInvocations(new List<Map<String, Object>>{ typedInputs });

        List<Invocable.Action.Result> results = action.invoke();
        Invocable.Action.Result actionResult = results[0];
        if (!actionResult.isSuccess()) {
            throw new ToolInvocationException(buildErrorMessage(actionResult.getErrors()));
        }

        return extractOutput(actionResult.getOutputParameters());
    }

    /**
     * Validates required top-level parameters and rebuilds any list-typed value
     * as a genuinely-typed Apex list, filtering the raw inputs map down to only
     * the parameter names the action actually declares (a hallucinated extra
     * key from the LLM must not reach Invocable.Action.setInvocations raw).
     */
    private static Map<String, Object> buildTypedInvocationMap(
        List<Invocable.Action.InputParameter> paramDescriptors,
        Map<String, Object> rawInputs
    ) {
        Map<String, Object> typed = new Map<String, Object>();
        for (Invocable.Action.InputParameter ip : paramDescriptors) {
            String name = ip.getName();
            Boolean provided = rawInputs != null && rawInputs.containsKey(name) && rawInputs.get(name) != null;

            if (ip.getRequired() == true && !provided) {
                throw new IllegalArgumentException('Missing required input parameter: ' + name);
            }
            if (!provided) {
                continue;
            }

            Boolean isCollection = ip.getMaxOccurs() != null && ip.getMaxOccurs() > 1;
            typed.put(name, isCollection
                ? buildTypedList(rawInputs.get(name), ip.getType(), ip.getApexClass(), name)
                : rawInputs.get(name));
        }
        return typed;
    }

    private static Object buildTypedList(Object rawValue, String primitiveType, String apexClass, String paramName) {
        String elementTypeName = String.isNotBlank(apexClass)
            ? apexClass.replace('$', '.')
            : mapDescribeTypeToApexTypeName(primitiveType);

        Type listType = Type.forName('List<' + elementTypeName + '>');
        if (listType == null) {
            throw new IllegalArgumentException(
                'Could not resolve Apex type for list parameter "' + paramName + '": List<' + elementTypeName + '>'
            );
        }

        try {
            return JSON.deserialize(JSON.serialize(rawValue), listType);
        } catch (Exception e) {
            throw new IllegalArgumentException(
                'Input parameter "' + paramName + '" does not match the expected shape: ' + e.getMessage()
            );
        }
    }

    private static String extractOutput(Map<String, Object> outputParameters) {
        if (outputParameters == null || outputParameters.isEmpty()) {
            return '{}';
        }
        // Every tool's Output class exposes exactly one field, resultJson, already holding
        // the tool's fully-serialized result — return it directly rather than re-wrapping
        // it in another JSON object, which would double-escape it.
        if (outputParameters.containsKey('resultJson')) {
            Object resultJson = outputParameters.get('resultJson');
            return resultJson == null ? '{}' : String.valueOf(resultJson);
        }
        return JSON.serialize(outputParameters);
    }

    private static String buildErrorMessage(List<Invocable.Action.Error> errors) {
        if (errors == null || errors.isEmpty()) {
            return 'Tool execution failed for an unknown reason.';
        }
        List<String> messages = new List<String>();
        for (Invocable.Action.Error err : errors) {
            messages.add(err.getMessage());
        }
        return String.join(messages, '; ');
    }

    private static String mapDescribeTypeToApexTypeName(String describeType) {
        if (String.isBlank(describeType)) {
            return 'String';
        }
        switch on describeType.toUpperCase() {
            when 'STRING' { return 'String'; }
            when 'BOOLEAN' { return 'Boolean'; }
            when 'INTEGER' { return 'Integer'; }
            when 'DOUBLE', 'DECIMAL', 'CURRENCY', 'PERCENT' { return 'Decimal'; }
            when 'LONG' { return 'Long'; }
            when 'DATE' { return 'Date'; }
            when 'DATETIME' { return 'Datetime'; }
            when 'TIME' { return 'Time'; }
            when 'ID' { return 'Id'; }
            when else { return 'String'; }
        }
    }

    // ─── DML bridge (data-modifying tools) ───────────────────────────────────

    // Session ID from the VF page is required here — named credentials cannot be used
    // for same-org callouts where the session must belong to the running user.
    @SuppressWarnings('PMD.ApexSuggestUsingNamedCredential')
    private static String executeViaDmlBridge(
        ApexAgent_Tool__c tool,
        Map<String, Object> inputs
    ) {
        // getContent() is unsupported inside test methods (a hard Apex platform
        // restriction, not something a mock can work around), so tests substitute
        // a dummy session id — the DML-bridge callout itself is still fully
        // exercised and mockable via HttpCalloutMock.
        String sessionId = Test.isRunningTest()
            ? 'test-session-id'
            : Page.ApexAgentSession.getContent().toString().trim();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/apexrest/ApexAgent/dml-bridge');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + sessionId); //NOPMD - session ID from VF page required for same-org callout
        req.setTimeout(DML_BRIDGE_TIMEOUT_MS);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'executionName' => tool.Apex_Class_Name__c,
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

    public class ToolInvocationException extends Exception {}
}
