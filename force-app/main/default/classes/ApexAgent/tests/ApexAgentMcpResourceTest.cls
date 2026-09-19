/**
 * Verifies ApexAgentMcpResource's authenticated-branch behavior: Origin
 * rejection, the no-fallback 404 guards, per-server tool scoping and
 * readOnlyHint annotations, tools/call execution and logging, and JSON-RPC
 * protocol errors.
 *
 * The Guest-branch 401 challenge is not covered here - it requires an actual
 * Site Guest User, which test context can't see without @isTest(SeeAllData=true),
 * and it was already verified end-to-end against the live org (401 status,
 * correct WWW-Authenticate resource_metadata URL) before this class was written.
 */
@IsTest
private class ApexAgentMcpResourceTest {

    private static Id mcpServerId;
    private static Id inactiveServerId;

    @TestSetup
    static void setup() {
        ApexAgent_MCP__c activeServer = new ApexAgent_MCP__c(
            Name = 'Test MCP Server',
            MCP_API_Name__c = 'testserver',
            Active__c = true
        );
        ApexAgent_MCP__c inactiveServer = new ApexAgent_MCP__c(
            Name = 'Inactive MCP Server',
            MCP_API_Name__c = 'inactiveserver',
            Active__c = false
        );
        insert new List<ApexAgent_MCP__c>{ activeServer, inactiveServer };

        String readOnlySchema = JSON.serialize(new Map<String, Object>{
            'type' => 'function',
            'function' => new Map<String, Object>{
                'name' => 'GetObjectApiName',
                'description' => 'Resolves the object type of a record ID.',
                'parameters' => new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{
                        'recordId' => new Map<String, Object>{ 'type' => 'string' }
                    },
                    'additionalProperties' => false
                }
            }
        });
        String dmlSchema = JSON.serialize(new Map<String, Object>{
            'type' => 'function',
            'function' => new Map<String, Object>{
                'name' => 'FakeDmlTool',
                'description' => 'A stand-in DML-modifying tool, never actually invoked.',
                'parameters' => new Map<String, Object>{ 'type' => 'object', 'properties' => new Map<String, Object>() }
            }
        });

        ApexAgent_Tool__c readOnlyTool = new ApexAgent_Tool__c(
            Name = 'Get Object Api Name',
            Apex_Class_Name__c = 'GetObjectApiName',
            Modifies_Salesforce_Data__c = false,
            Schema__c = readOnlySchema
        );
        ApexAgent_Tool__c dmlTool = new ApexAgent_Tool__c(
            Name = 'Fake Dml Tool',
            Apex_Class_Name__c = 'FakeDmlTool',
            Modifies_Salesforce_Data__c = true,
            Schema__c = dmlSchema
        );
        // Real tool, deliberately never mapped to activeServer - proves
        // tools/call scoping rejects it even though it exists in the org.
        ApexAgent_Tool__c unmappedTool = new ApexAgent_Tool__c(
            Name = 'Get Field Details',
            Apex_Class_Name__c = 'GetFieldDetails',
            Modifies_Salesforce_Data__c = false,
            Schema__c = readOnlySchema.replace('GetObjectApiName', 'GetFieldDetails')
        );
        insert new List<ApexAgent_Tool__c>{ readOnlyTool, dmlTool, unmappedTool };

        insert new List<ApexAgent_MCP_Tool_Map__c>{
            new ApexAgent_MCP_Tool_Map__c(MCP__c = activeServer.Id, Tool__c = readOnlyTool.Id, Active__c = true),
            new ApexAgent_MCP_Tool_Map__c(MCP__c = activeServer.Id, Tool__c = dmlTool.Id, Active__c = true)
        };
    }

    private static RestRequest buildRequest(String pathSuffix, String bodyJson) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ApexAgent/mcp/' + pathSuffix;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(bodyJson);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return req;
    }

    private static Map<String, Object> parseResponse() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    @IsTest
    static void testGuardClauses() {
        String discoverBody = '{"jsonrpc":"2.0","id":1,"method":"server/discover"}';

        // Site.getBaseUrl() is null in test context, so any Origin fails closed
        // here; the real host comparison is covered by testOriginMatching.
        buildRequest('testserver', discoverBody);
        RestContext.request.addHeader('Origin', 'https://evil.example.com');
        ApexAgentMcpResource.handleRequest();
        Assert.areEqual(403, RestContext.response.statusCode, 'An Origin that cannot be confirmed should be rejected');

        // No server name segment at all.
        buildRequest('', discoverBody);
        ApexAgentMcpResource.handleRequest();
        Assert.areEqual(404, RestContext.response.statusCode, 'A blank server name should 404, not fall back to any default');

        // A path segment outside the API-name charset never reaches routing.
        buildRequest('bad%22name', discoverBody);
        ApexAgentMcpResource.handleRequest();
        Assert.areEqual(404, RestContext.response.statusCode, 'A name with characters no API name can contain should 404');

        // Server name that doesn't resolve to any record.
        buildRequest('doesnotexist', discoverBody);
        ApexAgentMcpResource.handleRequest();
        Assert.areEqual(404, RestContext.response.statusCode, 'Unknown server name should 404');

        // Server exists but is inactive.
        buildRequest('inactiveserver', discoverBody);
        ApexAgentMcpResource.handleRequest();
        Assert.areEqual(404, RestContext.response.statusCode, 'Inactive server should 404 just like an unknown one');
    }

    @IsTest
    static void testServerDiscoverAndScopedToolsList() {
        buildRequest('testserver', '{"jsonrpc":"2.0","id":1,"method":"server/discover"}');
        ApexAgentMcpResource.handleRequest();
        Map<String, Object> discoverResult = (Map<String, Object>) parseResponse().get('result');
        Assert.areEqual('complete', discoverResult.get('resultType'), 'server/discover should report complete');

        buildRequest('testserver', '{"jsonrpc":"2.0","id":2,"method":"tools/list"}');
        ApexAgentMcpResource.handleRequest();
        Map<String, Object> listResult = (Map<String, Object>) parseResponse().get('result');
        List<Object> tools = (List<Object>) listResult.get('tools');

        Assert.areEqual(2, tools.size(), 'Only the two tools mapped to this server should be listed - not the unmapped one');

        Map<String, Boolean> readOnlyByName = new Map<String, Boolean>();
        for (Object t : tools) {
            Map<String, Object> tool = (Map<String, Object>) t;
            Map<String, Object> annotations = (Map<String, Object>) tool.get('annotations');
            readOnlyByName.put((String) tool.get('name'), (Boolean) annotations.get('readOnlyHint'));
        }
        Assert.areEqual(true, readOnlyByName.get('GetObjectApiName'), 'Non-DML tool should carry readOnlyHint=true');
        Assert.areEqual(false, readOnlyByName.get('FakeDmlTool'), 'DML tool should carry readOnlyHint=false');
    }

    @IsTest
    static void testToolsCallSuccessAndLogging() {
        ApexAgent_MCP__c server = [SELECT Id FROM ApexAgent_MCP__c WHERE MCP_API_Name__c = 'testserver'];
        String body = JSON.serialize(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => 3,
            'method' => 'tools/call',
            'params' => new Map<String, Object>{
                'name' => 'GetObjectApiName',
                'arguments' => new Map<String, Object>{ 'recordId' => UserInfo.getUserId() }
            }
        });

        Test.startTest();
        buildRequest('testserver', body);
        ApexAgentMcpResource.handleRequest();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) parseResponse().get('result');
        Assert.areEqual(false, result.get('isError'), 'A DML-free tool call should succeed inline with no callout mock needed');

        List<ApexAgent_Tool_Log__c> logs = [
            SELECT MCP__c, Message_Log__c, Status__c, Tool_Name__c
            FROM ApexAgent_Tool_Log__c
            WHERE MCP__c = :server.Id
        ];
        Assert.areEqual(1, logs.size(), 'The tools/call should have written exactly one Tool_Log__c');
        Assert.areEqual(server.Id, logs[0].MCP__c, 'MCP__c should be set');
        Assert.isNull(logs[0].Message_Log__c, 'Message_Log__c should stay null for an MCP-originated call');
        Assert.areEqual('Success', logs[0].Status__c, 'Status should be normalized to the same casing the Agentforce path uses');
    }

    @IsTest
    static void testToolsCallErrorsAndProtocolErrors() {
        ApexAgent_MCP__c server = [SELECT Id FROM ApexAgent_MCP__c WHERE MCP_API_Name__c = 'testserver'];

        // Real tool in the org, but not mapped to this server - protocol error, no log written.
        String unmappedCall = JSON.serialize(new Map<String, Object>{
            'jsonrpc' => '2.0', 'id' => 4, 'method' => 'tools/call',
            'params' => new Map<String, Object>{ 'name' => 'GetFieldDetails', 'arguments' => new Map<String, Object>() }
        });
        buildRequest('testserver', unmappedCall);
        ApexAgentMcpResource.handleRequest();
        Map<String, Object> unmappedError = (Map<String, Object>) parseResponse().get('error');
        Assert.areEqual(-32602, (Integer) unmappedError.get('code'), 'An unmapped tool should be a protocol error');
        Assert.isTrue(
            [SELECT COUNT() FROM ApexAgent_Tool_Log__c WHERE MCP__c = :server.Id] == 0,
            'Rejecting an unmapped tool before execution should not write a Tool_Log__c'
        );

        // Malformed JSON body.
        buildRequest('testserver', '{not valid json');
        ApexAgentMcpResource.handleRequest();
        Map<String, Object> parseError = (Map<String, Object>) parseResponse().get('error');
        Assert.areEqual(-32700, (Integer) parseError.get('code'), 'Malformed JSON should be a parse error');
        Assert.areEqual(400, RestContext.response.statusCode, 'A parse error should be HTTP 400');

        // Unknown JSON-RPC method.
        buildRequest('testserver', '{"jsonrpc":"2.0","id":5,"method":"notARealMethod"}');
        ApexAgentMcpResource.handleRequest();
        Assert.areEqual(404, RestContext.response.statusCode, 'An unrecognized method should 404');
        Map<String, Object> methodError = (Map<String, Object>) parseResponse().get('error');
        Assert.areEqual(-32601, (Integer) methodError.get('code'), 'Unknown method should be method-not-found');
    }

    @IsTest
    static void testMalformedRequestsAndNotifications() {
        // Each of these used to throw an unhandled exception (HTTP 500).
        Map<String, Integer> expectedCodeByBody = new Map<String, Integer>{
            'null' => -32600,
            '[1,2]' => -32600,
            '"just a string"' => -32600,
            '{"jsonrpc":"2.0","id":1,"method":5}' => -32600,
            '{"jsonrpc":"2.0","id":1}' => -32600,
            '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":"x"}' => -32602,
            '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":[1]}' => -32602,
            '{"jsonrpc":"2.0","id":1,"method":"tools/call"}' => -32602,
            '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":5}}' => -32602,
            '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"GetObjectApiName","arguments":"x"}}' => -32602,
            '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"GetObjectApiName","arguments":[1]}}' => -32602
        };
        for (String body : expectedCodeByBody.keySet()) {
            buildRequest('testserver', body);
            ApexAgentMcpResource.handleRequest();
            Assert.areEqual(400, RestContext.response.statusCode, 'Malformed body should be HTTP 400: ' + body);
            Map<String, Object> error = (Map<String, Object>) parseResponse().get('error');
            Assert.areEqual(expectedCodeByBody.get(body), (Integer) error.get('code'), 'Wrong JSON-RPC code for: ' + body);
        }

        // None of the rejected tools/call bodies above should have reached the tool.
        Assert.areEqual(0, [SELECT COUNT() FROM ApexAgent_Tool_Log__c], 'Rejected requests should not write a Tool_Log__c');

        // A message with no id is a notification: 202 Accepted and no body,
        // whether or not the method is one this server knows.
        for (String notification : new List<String>{
            '{"jsonrpc":"2.0","method":"notifications/initialized"}',
            '{"jsonrpc":"2.0","method":"tools/list"}'
        }) {
            buildRequest('testserver', notification);
            ApexAgentMcpResource.handleRequest();
            Assert.areEqual(202, RestContext.response.statusCode, 'A notification should be accepted: ' + notification);
            Assert.isNull(RestContext.response.responseBody, 'A notification response must have no body');
        }
    }

    @IsTest
    static void testOriginMatching() {
        String siteBaseUrl = 'https://myorg.my.salesforce-sites.com/mcpsite';

        Assert.isTrue(
            ApexAgentMcpResource.matchesSiteOrigin('https://myorg.my.salesforce-sites.com', siteBaseUrl),
            'The site\'s own origin should match, ignoring the path prefix'
        );
        Assert.isTrue(
            ApexAgentMcpResource.matchesSiteOrigin('HTTPS://MyOrg.My.Salesforce-Sites.com', siteBaseUrl),
            'Origin comparison should be case-insensitive'
        );
        Assert.isFalse(
            ApexAgentMcpResource.matchesSiteOrigin('http://myorg.my.salesforce-sites.com', siteBaseUrl),
            'A different scheme is a different origin'
        );
        Assert.isFalse(
            ApexAgentMcpResource.matchesSiteOrigin('https://evil.example.com', siteBaseUrl),
            'A different host should be rejected'
        );
        Assert.isFalse(
            ApexAgentMcpResource.matchesSiteOrigin('https://myorg.my.salesforce-sites.com.evil.example.com', siteBaseUrl),
            'A host that merely starts with the site host should be rejected'
        );
        Assert.isFalse(
            ApexAgentMcpResource.matchesSiteOrigin('https://myorg.my.salesforce-sites.com', null),
            'With no site URL to compare against, fail closed'
        );
    }
}
