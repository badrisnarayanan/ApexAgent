/**
 * Verifies the guest-accessible Protected Resource Metadata document: the
 * per-server resource URL, the authorization server, the advertised scopes,
 * and the 404 when no server name is in the path.
 */
@IsTest
private class ApexAgentMcpPrmTest {

    private static void buildRequest(String pathSuffix) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ApexAgent/prm/' + pathSuffix;
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void testMetadataDocumentAndMissingServerName() {
        buildRequest('testserver');
        ApexAgentMcpProtectedResourceMetadata.getMetadata();

        Assert.areEqual('application/json', RestContext.response.headers.get('Content-Type'), 'Should respond with JSON');
        Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        // Site.getBaseUrl() is null in test context, so only the path the
        // class appends can be asserted here.
        Assert.isTrue(
            ((String) metadata.get('resource')).endsWith('/services/apexrest/ApexAgent/mcp/testserver'),
            'resource should point at this server\'s own MCP endpoint'
        );
        List<Object> authServers = (List<Object>) metadata.get('authorization_servers');
        Assert.areEqual(1, authServers.size(), 'Exactly one authorization server should be advertised');
        Assert.areEqual(URL.getOrgDomainUrl().toExternalForm(), authServers[0], 'The org itself is the authorization server');
        Assert.areEqual(
            new List<Object>{ 'api', 'refresh_token' },
            (List<Object>) metadata.get('scopes_supported'),
            'Scopes should match the External Client App\'s configured OAuth scopes'
        );

        // The server name is read from the path only, never validated against
        // a record, so a name that exists nowhere still gets a document.
        buildRequest('nosuchserver');
        ApexAgentMcpProtectedResourceMetadata.getMetadata();
        Map<String, Object> unknownServerMetadata = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.isTrue(
            ((String) unknownServerMetadata.get('resource')).endsWith('/ApexAgent/mcp/nosuchserver'),
            'PRM is guest-accessible and must not query for the server'
        );

        // No server name segment at all.
        buildRequest('');
        ApexAgentMcpProtectedResourceMetadata.getMetadata();
        Assert.areEqual(404, RestContext.response.statusCode, 'A blank server name should 404');
        Assert.isNull(RestContext.response.responseBody, 'The 404 should carry no metadata document');
    }
}
