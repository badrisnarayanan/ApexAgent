/**
 * Verifies ApexAgentDmlBridgeResource writes a single, valid JSON payload
 * directly to the response body (no platform double-encoding) on both the
 * success and error paths.
 */
@IsTest
private class ApexAgentDmlBridgeResourceTest {

    @IsTest
    static void testExecuteSuccessWritesRawJsonBody() {
        Map<String, Object> requestBody = new Map<String, Object>{
            'executionType' => 'Apex',
            'executionName' => 'GetObjectApiName',
            'inputs' => new Map<String, Object>{ 'recordId' => UserInfo.getUserId() }
        };
        RestContext.request = new RestRequest();
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        RestContext.response = new RestResponse();

        Test.startTest();
        ApexAgentDmlBridgeResource.execute();
        Test.stopTest();

        String responseBody = RestContext.response.responseBody.toString();
        Assert.isFalse(responseBody.startsWith('"'), 'Response must not be double-JSON-encoded');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Assert.areEqual('User', parsed.get('objectApiName'), 'Should decode the tool result directly');
    }

    @IsTest
    static void testExecuteErrorWritesStatus500AndErrorBody() {
        Map<String, Object> requestBody = new Map<String, Object>{
            'executionType' => 'Apex',
            'executionName' => 'DoesNotExistTool',
            'inputs' => new Map<String, Object>()
        };
        RestContext.request = new RestRequest();
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        RestContext.response = new RestResponse();

        Test.startTest();
        ApexAgentDmlBridgeResource.execute();
        Test.stopTest();

        Assert.areEqual(500, RestContext.response.statusCode, 'Unknown tool class should return 500');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.isTrue(String.valueOf(parsed.get('error')).contains('DoesNotExistTool'), 'Error should name the missing class');
        Assert.isNotNull(parsed.get('stackTrace'), 'Error body should include a stack trace');
    }
}
