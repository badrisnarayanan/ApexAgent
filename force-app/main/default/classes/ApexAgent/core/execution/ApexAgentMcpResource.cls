/**
 * The MCP endpoint for ApexAgent, exposed via a Site's Guest User Profile.
 * Routes by server name: /services/apexrest/ApexAgent/mcp/<MCP_API_Name__c>.
 * There is no bare /ApexAgent/mcp fallback - a server name is always required.
 *
 * A single urlMapping serves two audiences, differentiated by the platform
 * before this code ever runs:
 *  - No/invalid Bearer token -> the platform runs this transaction as the
 *    Site's Guest User. That branch shapes the 401 challenge MCP clients
 *    need for OAuth discovery (RFC 9728) and nothing else - no data access.
 *    Crucially, the guest branch never queries ApexAgent_MCP__c: the guest
 *    profile has zero object permissions on it, so any query would come back
 *    empty and every unauthenticated request would 404 instead of issuing
 *    the 401 challenge, breaking OAuth discovery entirely. The server name
 *    is extracted as a raw string from the URL and used as-is.
 *  - A valid Bearer token -> the platform authenticates the request as the
 *    real token holder before this code runs, and this transaction executes
 *    with their actual profile, permission sets, sharing, and FLS. Only this
 *    branch resolves the server name against ApexAgent_MCP__c and scopes
 *    tools to whatever's mapped via ApexAgent_MCP_Tool_Map__c.
 *
 * JSON-RPC dispatch implements server/discover, tools/list, and tools/call.
 *
 * Every request is checked against the Origin header (RFC 9728 / MCP
 * transport security requirement) before either branch runs, to prevent
 * DNS-rebinding-style cross-origin abuse of the guest-accessible path.
 */
@RestResource(urlMapping='/ApexAgent/mcp/*')
global with sharing class ApexAgentMcpResource {

    private static final String PROTOCOL_VERSION = '2026-07-28';
    private static final String SERVER_NAME = 'ApexAgent';
    private static final String SERVER_VERSION = '1.0.0';
    private static final String PATH_MARKER = '/ApexAgent/mcp/';
    private static final String SERVER_NAME_PATTERN = '[A-Za-z0-9_-]+';

    @HttpPost
    global static void handleRequest() {
        if (!isOriginAllowed()) {
            RestContext.response.statusCode = 403;
            respondError(null, ApexAgentJsonRpcErrorCodes.ORIGIN_NOT_ALLOWED, 'Origin not allowed');
            return;
        }

        String serverName = extractServerName();
        if (String.isBlank(serverName)) {
            RestContext.response.statusCode = 404;
            respondError(null, ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'MCP server name required in path');
            return;
        }

        if (UserInfo.getUserType() == 'Guest') {
            challengeForAuthorization(serverName);
            return;
        }

        ApexAgent_MCP__c mcpServer = resolveActiveServer(serverName);
        if (mcpServer == null) {
            RestContext.response.statusCode = 404;
            respondError(null, ApexAgentJsonRpcErrorCodes.UNKNOWN_MCP_SERVER, 'Unknown or inactive MCP server: ' + serverName);
            return;
        }

        dispatch(mcpServer.Id);
    }

    /**
     * MCP clients that are not browser-embedded (Claude Code, Claude
     * Desktop, MCP Inspector, server-side agents) never send an Origin
     * header at all, so an absent header is allowed. A present header is
     * only ever legitimate if it names this same site - any third-party
     * page trying to drive a browser into calling this endpoint gets
     * rejected here before either the guest or authenticated branch runs.
     */
    private static Boolean isOriginAllowed() {
        String origin = RestContext.request.headers.get('Origin');
        if (String.isBlank(origin)) {
            return true;
        }
        return matchesSiteOrigin(origin, Site.getBaseUrl());
    }

    /**
     * Split out from isOriginAllowed() because Site.getBaseUrl() is null in
     * test context, which would otherwise leave the real comparison untested.
     */
    @TestVisible
    private static Boolean matchesSiteOrigin(String origin, String siteBaseUrl) {
        if (String.isBlank(siteBaseUrl)) {
            // Can't confirm the allowed origin - fail closed rather than
            // let new Url(null) throw an unhandled StringException.
            return false;
        }
        Url siteUrl = new Url(siteBaseUrl);
        String allowedOrigin = siteUrl.getProtocol() + '://' + siteUrl.getHost();
        return origin.equalsIgnoreCase(allowedOrigin);
    }

    /**
     * Pulls the server name segment out of the raw request URI - deliberately
     * string-only, no SOQL, since this runs in the guest branch too.
     */
    private static String extractServerName() {
        String uri = RestContext.request.requestURI;
        Integer markerIndex = uri.indexOf(PATH_MARKER);
        if (markerIndex == -1) {
            return null;
        }
        String remainder = uri.substring(markerIndex + PATH_MARKER.length());
        Integer slashIndex = remainder.indexOf('/');
        String name = slashIndex == -1 ? remainder : remainder.substring(0, slashIndex);
        // Same charset MCP_API_Name__c enforces, so nothing that could never
        // match a record (or break out of the quoted WWW-Authenticate value
        // the guest branch builds from this) gets past here.
        return Pattern.matches(SERVER_NAME_PATTERN, name) ? name : null;
    }

    private static ApexAgent_MCP__c resolveActiveServer(String serverName) {
        List<ApexAgent_MCP__c> servers = [
            SELECT Id
            FROM ApexAgent_MCP__c
            WHERE MCP_API_Name__c = :serverName AND Active__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        return servers.isEmpty() ? null : servers[0];
    }

    private static void dispatch(Id mcpServerId) {
        Object parsedBody;
        try {
            parsedBody = JSON.deserializeUntyped(RestContext.request.requestBody.toString());
        } catch (Exception parseError) {
            respondBadRequest(null, ApexAgentJsonRpcErrorCodes.PARSE_ERROR, 'Parse error');
            return;
        }

        if (!(parsedBody instanceof Map<String, Object>)) {
            respondBadRequest(null, ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'Request body must be a single JSON object');
            return;
        }
        Map<String, Object> requestBody = (Map<String, Object>) parsedBody;

        // A message without an id is a JSON-RPC notification: no response
        // body, just acknowledgement (2026-07-28 Streamable HTTP, "Sending
        // Messages"). This revision defines no client notifications, so
        // there's nothing to act on - e.g. a legacy client's
        // notifications/initialized is accepted and ignored.
        if (!requestBody.containsKey('id')) {
            RestContext.response.statusCode = 202;
            return;
        }

        Object id = requestBody.get('id');
        Object methodValue = requestBody.get('method');
        if (!(methodValue instanceof String)) {
            respondBadRequest(id, ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'method must be a string');
            return;
        }
        String method = (String) methodValue;

        Object paramsValue = requestBody.get('params');
        if (paramsValue != null && !(paramsValue instanceof Map<String, Object>)) {
            respondBadRequest(id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, 'params must be an object');
            return;
        }

        if (method == 'server/discover') {
            respondServerDiscover(id);
        } else if (method == 'tools/list') {
            respondToolsList(id, mcpServerId);
        } else if (method == 'tools/call') {
            respondToolsCall(id, (Map<String, Object>) paramsValue, mcpServerId);
        } else {
            RestContext.response.statusCode = 404;
            respondError(id, ApexAgentJsonRpcErrorCodes.METHOD_NOT_FOUND, 'Method not found: ' + method);
        }
    }

    private static void respondServerDiscover(Object id) {
        Map<String, Object> result = new Map<String, Object>{
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
        respondSuccess(id, result);
    }

    /**
     * Lists every tool mapped to this MCP server with a valid precomputed
     * schema, reusing the same OpenAI-shaped definitions the agent loop
     * sends the LLM (ApexAgentToolSchemaBuilder) and remapping `parameters`
     * to MCP's `inputSchema`. Each tool carries a readOnlyHint annotation
     * (https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)
     * derived from Modifies_Salesforce_Data__c, so a client can tell which
     * tools are safe to call without confirmation.
     */
    private static void respondToolsList(Object id, Id mcpServerId) {
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

        respondSuccess(id, new Map<String, Object>{
            'resultType' => 'complete',
            'tools' => tools,
            // Inspector's client-side validation requires ttlMs as a number
            // even though the spec prose doesn't flag it as strictly
            // required - 5 minutes, matching the spec's own example value.
            'ttlMs' => 300000,
            'cacheScope' => 'private'
        });
    }

    /**
     * Executes a tool via the same ApexAgentToolExecutor path the agent loop
     * uses, running with the real authenticated caller's own permissions,
     * sharing, and FLS (this only runs in the authenticated branch - Guest
     * never reaches dispatch()). A missing/unknown tool name, or a tool not
     * mapped to this server, is a protocol error (invalid request), not a
     * tool-execution error, per the MCP spec's distinction between the two.
     *
     * Always executes inline (forceInline=true), never through the DML
     * bridge: the bridge exists so the agentic loop can still make its next
     * LLM callout after a DML tool runs in the same transaction. A tools/call
     * request is a single synchronous REST response with no further callout
     * afterwards, so that isolation isn't needed here.
     */
    private static void respondToolsCall(Object id, Map<String, Object> params, Id mcpServerId) {
        Object nameValue = params?.get('name');
        if (!(nameValue instanceof String) || String.isBlank((String) nameValue)) {
            respondBadRequest(id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, 'params.name is required and must be a string');
            return;
        }
        Object argumentsValue = params.get('arguments');
        if (argumentsValue != null && !(argumentsValue instanceof Map<String, Object>)) {
            respondBadRequest(id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, 'params.arguments must be an object');
            return;
        }

        String toolName = (String) nameValue;
        Map<String, ApexAgent_Tool__c> toolsByName = queryToolsByName(mcpServerId);
        if (!toolsByName.containsKey(toolName)) {
            respondError(id, ApexAgentJsonRpcErrorCodes.INVALID_PARAMS, 'Unknown tool: ' + toolName);
            return;
        }

        ApexAgentApiTypes.ToolCall toolCall = new ApexAgentApiTypes.ToolCall();
        toolCall.id = 'mcp-' + String.valueOf(id);
        toolCall.type = 'function';
        toolCall.function = new ApexAgentApiTypes.ToolCallFunction();
        toolCall.function.name = toolName;
        toolCall.function.arguments = JSON.serialize(
            argumentsValue == null ? new Map<String, Object>() : argumentsValue
        );

        Datetime startedAt = Datetime.now();
        ApexAgentExecTypes.ToolResult toolResult = ApexAgentToolExecutor.execute(toolsByName, toolCall, true);
        Datetime endedAt = Datetime.now();
        Boolean isError = toolResult.status == 'error';

        logToolCall(mcpServerId, toolResult, startedAt, endedAt);

        respondSuccess(id, new Map<String, Object>{
            'resultType' => 'complete',
            'content' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'text',
                    'text' => isError ? toolResult.errorMessage : toolResult.output
                }
            },
            'isError' => isError
        });
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
        entry.status = toolResult.status == 'error' ? 'Error' : 'Success';
        entry.errorMessage = toolResult.errorMessage;
        entry.stackTrace = toolResult.errorStackTrace;
        entry.startedAt = startedAt;
        entry.endedAt = endedAt;
        ApexAgentLogger.logMcpToolCall(mcpServerId, entry);
    }

    /**
     * Every tool actively mapped to this MCP server via ApexAgent_MCP_Tool_Map__c
     * with a generated schema, keyed by Apex_Class_Name__c - the same key
     * ApexAgentToolExecutor and ApexAgentToolSchemaBuilder both expect.
     * WITH USER_MODE enforces the real caller's sharing and FLS, consistent
     * with how ApexAgentTopicLoader queries tools for the Agentforce path.
     */
    private static Map<String, ApexAgent_Tool__c> queryToolsByName(Id mcpServerId) {
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

    private static void respondSuccess(Object id, Object result) {
        Map<String, Object> body = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => id,
            'result' => result
        };
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    /** A structurally malformed message: HTTP 400 alongside the JSON-RPC error. */
    private static void respondBadRequest(Object id, Integer code, String message) {
        RestContext.response.statusCode = 400;
        respondError(id, code, message);
    }

    private static void respondError(Object id, Integer code, String message) {
        Map<String, Object> body = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => id,
            'error' => new Map<String, Object>{
                'code' => code,
                'message' => message
            }
        };
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    /**
     * Returns a specific MCP server's canonical endpoint URL, used as the
     * `resource` value in its protected resource metadata document and as
     * the audience clients bind their token requests to.
     */
    public static String getResourceUrl(String serverName) {
        return Site.getBaseUrl() + '/services/apexrest/ApexAgent/mcp/' + serverName;
    }

    private static void challengeForAuthorization(String serverName) {
        String resourceMetadataUrl = Site.getBaseUrl() + '/services/apexrest/ApexAgent/prm/' + serverName;
        RestContext.response.statusCode = 401;
        RestContext.response.addHeader(
            'WWW-Authenticate',
            'Bearer resource_metadata="' + resourceMetadataUrl + '"'
        );
        respondError(null, ApexAgentJsonRpcErrorCodes.AUTHORIZATION_REQUIRED, 'Authorization required');
    }
}
