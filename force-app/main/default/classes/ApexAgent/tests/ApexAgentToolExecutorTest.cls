/**
 * Verifies ApexAgentToolExecutor routes non-DML tools inline and DML tools
 * through the REST bridge, and that both round-trip a single JSON payload
 * with no double-encoding (the bug fixed in ApexAgentDmlBridgeResource).
 */
@IsTest
private class ApexAgentToolExecutorTest {

    private static ApexAgentApiTypes.ToolCall buildToolCall(String id, String name, String argumentsJson) {
        ApexAgentApiTypes.ToolCall tc = new ApexAgentApiTypes.ToolCall();
        tc.id = id;
        tc.type = 'function';
        tc.function = new ApexAgentApiTypes.ToolCallFunction();
        tc.function.name = name;
        tc.function.arguments = argumentsJson;
        return tc;
    }

    private static ApexAgent_Tool__c buildTool(String apexClassName, Boolean modifiesData) {
        return new ApexAgent_Tool__c(
            Apex_Class_Name__c           = apexClassName,
            Modifies_Salesforce_Data__c = modifiesData
        );
    }

    @IsTest
    static void testExecuteInlineNonDmlToolSuccess() {
        ApexAgent_Tool__c tool = buildTool('GetObjectApiName', false);
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'GetObjectApiName' => tool
        };
        String args = JSON.serialize(new Map<String, Object>{ 'recordId' => UserInfo.getUserId() });
        ApexAgentApiTypes.ToolCall tc = buildToolCall('call-1', 'GetObjectApiName', args);

        Test.startTest();
        ApexAgentExecTypes.ToolResult result = ApexAgentToolExecutor.execute(toolsByName, tc);
        Test.stopTest();

        Assert.areEqual('success', result.status, 'Inline tool should succeed. errorMessage=' + result.errorMessage);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result.output);
        Assert.areEqual('User', parsed.get('objectApiName'), 'Should resolve the object type from the ID');
    }

    @IsTest
    static void testExecuteUnknownToolReturnsError() {
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>();
        ApexAgentApiTypes.ToolCall tc = buildToolCall('call-2', 'notRegistered', '{}');

        Test.startTest();
        ApexAgentExecTypes.ToolResult result = ApexAgentToolExecutor.execute(toolsByName, tc);
        Test.stopTest();

        Assert.areEqual('error', result.status, 'Unregistered tool should error');
        Assert.isTrue(result.errorMessage.contains('notRegistered'), 'Error should name the missing tool');
    }

    @IsTest
    static void testExecuteViaDmlBridgeRoundTripSuccess() {
        ApexAgent_Tool__c tool = buildTool('GetObjectApiName', true);
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'GetObjectApiName' => tool
        };
        String args = JSON.serialize(new Map<String, Object>{ 'recordId' => UserInfo.getUserId() });
        ApexAgentApiTypes.ToolCall tc = buildToolCall('call-3', 'GetObjectApiName', args);

        Test.setMock(HttpCalloutMock.class, new ApexAgentDmlBridgeRoundTripMock());
        Test.startTest();
        ApexAgentExecTypes.ToolResult result = ApexAgentToolExecutor.execute(toolsByName, tc);
        Test.stopTest();

        Assert.areEqual('success', result.status,
            'DML-bridged tool should succeed via the round trip. errorMessage=' + result.errorMessage);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result.output);
        Assert.areEqual('User', parsed.get('objectApiName'), 'Bridge response should decode without double-encoding');
    }

    @IsTest
    static void testExecuteViaDmlBridgeErrorSurfacesBridgeException() {
        ApexAgent_Tool__c tool = buildTool('NoSuchApexClass', true);
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'NoSuchApexClass' => tool
        };
        ApexAgentApiTypes.ToolCall tc = buildToolCall('call-4', 'NoSuchApexClass', '{}');

        Test.setMock(HttpCalloutMock.class, new ApexAgentDmlBridgeRoundTripMock());
        Test.startTest();
        ApexAgentExecTypes.ToolResult result = ApexAgentToolExecutor.execute(toolsByName, tc);
        Test.stopTest();

        Assert.areEqual('error', result.status, 'Bridge-side failure should surface as an error result');
        Assert.isTrue(result.errorMessage.contains('NoSuchApexClass'), 'Error should carry the original bridge-side message');
        Assert.isNotNull(result.errorStackTrace, 'Original bridge-side stack trace should be preserved');
    }
}
