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

        if (!'2.0'.equals(requestBody.get('jsonrpc'))) {
            ApexAgentJsonRpcResponder.error(400, readableId(requestBody), ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'jsonrpc must be "2.0"');
            return;
        }

        // A message without an id is a JSON-RPC notification: no response
        // body, just acknowledgement (2026-07-28 Streamable HTTP, "Sending
        // Messages"). This revision defines no client notifications, so
        // there's nothing to act on - e.g. a legacy client's
        // notifications/initialized is accepted and ignored.
        if (!requestBody.containsKey('id')) {
            ApexAgentJsonRpcResponder.accepted();
            return;
        }

        Object id = readableId(requestBody);
        if (id == null) {
            ApexAgentJsonRpcResponder.error(400, null, ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'id must be a string or an integer');
            return;
        }

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

        // Anything unexpected past validation (e.g. a USER_MODE query the
        // caller lacks access for) still has to come back as a JSON-RPC error
        // carrying the request's id, not the platform's own 500 error array.
        try {
            route(id, method, (Map<String, Object>) paramsValue, mcpServerId);
        } catch (Exception unexpected) {
            ApexAgentJsonRpcResponder.error(500, id, ApexAgentJsonRpcErrorCodes.INTERNAL_ERROR, 'Internal error: ' + unexpected.getMessage());
        }
    }

    private static void route(Object id, String method, Map<String, Object> params, Id mcpServerId) {
        if (method == 'server/discover') {
            ApexAgentJsonRpcResponder.success(id, buildServerDiscoverResult());
        } else if (method == 'tools/list') {
            ApexAgentJsonRpcResponder.success(id, ApexAgentMcpToolService.listTools(mcpServerId));
        } else if (method == 'tools/call') {
            handleToolsCall(id, params, mcpServerId);
        } else {
            // 404 + -32601 is what the 2026-07-28 transport spec requires for
            // an unimplemented method - not 200.
            ApexAgentJsonRpcResponder.error(404, id, ApexAgentJsonRpcErrorCodes.METHOD_NOT_FOUND, 'Method not found: ' + method);
        }
    }

    /**
     * The request's id if it's one MCP allows - a string or an integer, never
     * null - otherwise null. JSON.deserializeUntyped yields Integer or Long for
     * whole numbers and Decimal for anything with a fraction, so a Decimal id
     * is rejected along with objects, arrays, and booleans.
     */
    private static Object readableId(Map<String, Object> requestBody) {
        Object id = requestBody.get('id');
        return (id instanceof String || id instanceof Integer || id instanceof Long) ? id : null;
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
