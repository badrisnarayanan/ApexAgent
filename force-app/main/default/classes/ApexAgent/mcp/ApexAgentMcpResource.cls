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
 *    branch resolves the server name against ApexAgent_MCP__c and hands the
 *    request to ApexAgentMcpDispatcher.
 *
 * This class is only the entry point: Origin check, guest challenge, and
 * server lookup. JSON-RPC handling lives in ApexAgentMcpDispatcher, tool
 * listing/execution in ApexAgentMcpToolService.
 *
 * Every request is checked against the Origin header (RFC 9728 / MCP
 * transport security requirement) before either branch runs, to prevent
 * DNS-rebinding-style cross-origin abuse of the guest-accessible path.
 */
@RestResource(urlMapping='/ApexAgent/mcp/*')
global with sharing class ApexAgentMcpResource {

    private static final String PATH_MARKER = '/ApexAgent/mcp/';

    @HttpPost
    global static void handleRequest() {
        if (!isOriginAllowed()) {
            ApexAgentJsonRpcResponder.error(403, null, ApexAgentJsonRpcErrorCodes.ORIGIN_NOT_ALLOWED, 'Origin not allowed');
            return;
        }

        String serverName = ApexAgentMcpPathUtils.extractServerName(RestContext.request.requestURI, PATH_MARKER);
        if (String.isBlank(serverName)) {
            ApexAgentJsonRpcResponder.error(404, null, ApexAgentJsonRpcErrorCodes.INVALID_REQUEST, 'MCP server name required in path');
            return;
        }

        if (UserInfo.getUserType() == 'Guest') {
            challengeForAuthorization(serverName);
            return;
        }

        ApexAgent_MCP__c mcpServer = resolveActiveServer(serverName);
        if (mcpServer == null) {
            ApexAgentJsonRpcResponder.error(404, null, ApexAgentJsonRpcErrorCodes.UNKNOWN_MCP_SERVER, 'Unknown or inactive MCP server: ' + serverName);
            return;
        }

        ApexAgentMcpDispatcher.dispatch(mcpServer.Id);
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
        RestContext.response.addHeader(
            'WWW-Authenticate',
            'Bearer resource_metadata="' + resourceMetadataUrl + '"'
        );
        ApexAgentJsonRpcResponder.error(401, null, ApexAgentJsonRpcErrorCodes.AUTHORIZATION_REQUIRED, 'Authorization required');
    }
}
