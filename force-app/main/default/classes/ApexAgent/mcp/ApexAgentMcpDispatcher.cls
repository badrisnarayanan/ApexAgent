/**
 * JSON-RPC layer of the MCP endpoint: parses and validates the request body,
 * acknowledges notifications, and routes server/discover, tools/list, and
 * tools/call. Only reached from the authenticated branch of
 * ApexAgentMcpResource - never from the Guest branch.
 */
public with sharing class ApexAgentMcpDispatcher {

    private static final String PROTOCOL_VERSION = '2026-07-28';
    private static final String SERVER_NAME = 'ApexAgent';
    private static final String SERVER_VERSION = '1.0.0';

    public static void dispatch(Id mcpServerId) {
        Object parsedBody;
        try {
            parsedBody = JSON.deserializeUntyped(RestContext.request.requestBody.toString());
        } catch (Exception parseError) {
            ApexAgentJsonRpcResponder.error(400, null, ApexAgentJsonRpcErrorCodes.PARSE_ERROR, 'Parse error');
            return;
        }

        if (!(parsedBody instanceof Map<String, Object>)) {
            ApexAgentJsonRpcResponder.error(400, null, ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'Request body must be a single JSON object');
            return;
        }
        Map<String, Object> requestBody = (Map<String, Object>) parsedBody;

        // A message without an id is a JSON-RPC notification: no response
        // body, just acknowledgement (2026-07-28 Streamable HTTP, "Sending
        // Messages"). This revision defines no client notifications, so
        // there's nothing to act on - e.g. a legacy client's
        // notifications/initialized is accepted and ignored.
        if (!requestBody.containsKey('id')) {
            ApexAgentJsonRpcResponder.accepted();
            return;
        }

        Object id = requestBody.get('id');
        Object methodValue = requestBody.get('method');
        if (!(methodValue instanceof String)) {
            ApexAgentJsonRpcResponder.error(400, id, ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'method must be a string');
            return;
        }
        String method = (String) methodValue;

        Object paramsValue = requestBody.get('params');
        if (paramsValue != null && !(paramsValue instanceof Map<String, Object>)) {
            ApexAgentJsonRpcResponder.error(400, id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, 'params must be an object');
            return;
        }

        if (method == 'server/discover') {
            ApexAgentJsonRpcResponder.success(id, buildServerDiscoverResult());
        } else if (method == 'tools/list') {
            ApexAgentJsonRpcResponder.success(id, ApexAgentMcpToolService.listTools(mcpServerId));
        } else if (method == 'tools/call') {
            handleToolsCall(id, (Map<String, Object>) paramsValue, mcpServerId);
        } else {
            // 404 + -32601 is what the 2026-07-28 transport spec requires for
            // an unimplemented method - not 200.
            ApexAgentJsonRpcResponder.error(404, id, ApexAgentJsonRpcErrorCodes.METHOD_NOT_FOUND, 'Method not found: ' + method);
        }
    }

    private static Map<String, Object> buildServerDiscoverResult() {
        return new Map<String, Object>{
            'resultType' => 'complete',
            'supportedVersions' => new List<String>{ PROTOCOL_VERSION },
            'capabilities' => new Map<String, Object>{ 'tools' => new Map<String, Object>() },
            '_meta' => new Map<String, Object>{
                'io.modelcontextprotocol/serverInfo' => new Map<String, Object>{
                    'name' => SERVER_NAME,
                    'version' => SERVER_VERSION
                }
            },
            'instructions' => 'This server exposes ApexAgent tools over MCP.'
        };
    }

    /**
     * A malformed tools/call (missing or non-string name, non-object
     * arguments) is a 400 protocol error before any tool lookup happens; a
     * well-formed call to a tool that isn't available is -32602 at HTTP 200.
     */
    private static void handleToolsCall(Object id, Map<String, Object> params, Id mcpServerId) {
        Object nameValue = params?.get('name');
        if (!(nameValue instanceof String) || String.isBlank((String) nameValue)) {
            ApexAgentJsonRpcResponder.error(400, id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, 'params.name is required and must be a string');
            return;
        }
        Object argumentsValue = params.get('arguments');
        if (argumentsValue != null && !(argumentsValue instanceof Map<String, Object>)) {
            ApexAgentJsonRpcResponder.error(400, id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, 'params.arguments must be an object');
            return;
        }

        try {
            ApexAgentJsonRpcResponder.success(
                id,
                ApexAgentMcpToolService.callTool(mcpServerId, id, (String) nameValue, argumentsValue)
            );
        } catch (ApexAgentMcpToolService.UnknownToolException unknownTool) {
            ApexAgentJsonRpcResponder.error(id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, unknownTool.getMessage());
        }
    }
}
