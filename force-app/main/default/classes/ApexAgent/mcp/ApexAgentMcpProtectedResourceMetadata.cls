/**
 * Serves the MCP Protected Resource Metadata (RFC 9728) document that tells
 * an MCP client which authorization server to use, per MCP server:
 * /services/apexrest/ApexAgent/prm/<MCP_API_Name__c>.
 *
 * Must be guest-accessible: an MCP client fetches this document in response
 * to the 401 challenge issued by ApexAgentMcpResource, before it has any
 * token at all. Grant this class to the Site's Guest User Profile only - it
 * performs no DML and no SOQL, it only describes the resource from the URL.
 *
 * Deliberately not routed as /ApexAgent/mcp/<name>/prm: Salesforce's
 * documented urlMapping precedence only guarantees exact-beats-wildcard, not
 * wildcard-beats-wildcard, so it would be unverified whether that shape
 * reliably resolves here instead of to ApexAgentMcpResource's own
 * /ApexAgent/mcp/* mapping. /ApexAgent/prm/* diverges at the second path
 * segment, so there's no overlap to reason about.
 */
@RestResource(urlMapping='/ApexAgent/prm/*')
global with sharing class ApexAgentMcpProtectedResourceMetadata {

    private static final String PATH_MARKER = '/ApexAgent/prm/';

    @HttpGet
    global static void getMetadata() {
        String serverName = extractServerName();
        if (String.isBlank(serverName)) {
            RestContext.response.statusCode = 404;
            return;
        }

        Map<String, Object> metadata = new Map<String, Object>{
            'resource' => ApexAgentMcpResource.getResourceUrl(serverName),
            'authorization_servers' => new List<String>{ URL.getOrgDomainUrl().toExternalForm() },
            // Without this, a client with no other guidance falls back to
            // requesting every scope the org's AS supports org-wide (per
            // the org's own openid-configuration scopes_supported) rather
            // than just what this resource needs - Salesforce's authorize
            // endpoint then rejects the resulting scope string as too long.
            // Must match the External Client App's configured OAuth scopes.
            'scopes_supported' => new List<String>{ 'api', 'refresh_token' }
        };
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(metadata));
    }

    /**
     * String-only, no SOQL - this class is guest-accessible and must never
     * validate the server name against ApexAgent_MCP__c (see
     * ApexAgentMcpResource's class doc for why).
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
        return String.isBlank(name) ? null : name;
    }
}
