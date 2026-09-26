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
        ApexAgent_Tool__c tool = buildTool('ApexAgentGetObjectApiName', false);
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'ApexAgentGetObjectApiName' => tool
        };
        String args = JSON.serialize(new Map<String, Object>{ 'recordId' => UserInfo.getUserId() });
        ApexAgentApiTypes.ToolCall tc = buildToolCall('call-1', 'ApexAgentGetObjectApiName', args);

        Test.startTest();
        ApexAgentExecTypes.ToolResult result = ApexAgentToolExecutor.execute(toolsByName, tc);
        Test.stopTest();

        Assert.areEqual(ApexAgentExecTypes.STATUS_SUCCESS, result.status, 'Inline tool should succeed. errorMessage=' + result.errorMessage);
        Assert.isFalse(result.isError(), 'isError should be false for a successful result');
        Assert.areEqual('Success', ApexAgentLogger.toolLogStatus(result), 'A successful result should be logged as Success');
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

        Assert.areEqual(ApexAgentExecTypes.STATUS_ERROR, result.status, 'Unregistered tool should error');
        Assert.isTrue(result.isError(), 'isError should be true for an error result');
        Assert.areEqual('Error', ApexAgentLogger.toolLogStatus(result), 'An error result should be logged as Error');
        Assert.isTrue(result.errorMessage.contains('notRegistered'), 'Error should name the missing tool');
    }

    @IsTest
    static void testExecuteViaDmlBridgeRoundTripSuccess() {
        ApexAgent_Tool__c tool = buildTool('ApexAgentGetObjectApiName', true);
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'ApexAgentGetObjectApiName' => tool
        };
        String args = JSON.serialize(new Map<String, Object>{ 'recordId' => UserInfo.getUserId() });
        ApexAgentApiTypes.ToolCall tc = buildToolCall('call-3', 'ApexAgentGetObjectApiName', args);

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
    static void testExecuteForceInlineSkipsDmlBridgeEvenForDmlTool() {
        // A DML-modifying tool would normally route through the DML bridge
        // (an HTTP callout), which would throw here since no callout mock is
        // registered - success without a mock is itself proof forceInline
        // took the inline path instead.
        ApexAgent_Tool__c tool = buildTool('ApexAgentGetObjectApiName', true);
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'ApexAgentGetObjectApiName' => tool
        };
        String args = JSON.serialize(new Map<String, Object>{ 'recordId' => UserInfo.getUserId() });
        ApexAgentApiTypes.ToolCall tc = buildToolCall('call-5', 'ApexAgentGetObjectApiName', args);

        Test.startTest();
        ApexAgentExecTypes.ToolResult result = ApexAgentToolExecutor.execute(toolsByName, tc, true);
        Test.stopTest();

        Assert.areEqual('success', result.status,
            'forceInline should bypass the DML bridge and succeed with no callout mock. errorMessage=' + result.errorMessage);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result.output);
        Assert.areEqual('User', parsed.get('objectApiName'), 'Should still resolve the object type from the ID');
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

    @IsTest
    static void testToolThrownErrorKeepsToolStackFramesAheadOfExecutorFrames() {
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'ApexAgentGetObjectApiName' => buildTool('ApexAgentGetObjectApiName', false)
        };
        ApexAgentApiTypes.ToolCall tc = buildToolCall(
            'call-5', 'ApexAgentGetObjectApiName', JSON.serialize(new Map<String, Object>{ 'recordId' => 'not-an-id' })
        );

        Test.startTest();
        ApexAgentExecTypes.ToolResult result = ApexAgentToolExecutor.execute(toolsByName, tc);
        Test.stopTest();

        Assert.isTrue(result.isError(), 'A tool that throws should produce an error result');
        Assert.isTrue(result.errorMessage.contains('not a valid Salesforce ID'), 'Should carry the tool\'s own message');
        String trace = result.errorStackTrace;
        Assert.isTrue(trace.contains('Class.ApexAgentGetObjectApiName.processOne'), 'Trace should include the frame in the tool that threw. Trace=' + trace);
        Assert.isTrue(
            trace.indexOf('Class.ApexAgentGetObjectApiName') < trace.indexOf('Class.ApexAgentToolExecutor.executeInline'),
            'Tool frames should come before the executor frames. Trace=' + trace
        );

        // A later successful call must not inherit the earlier failure's trace
        tc = buildToolCall('call-6', 'ApexAgentGetObjectApiName', JSON.serialize(new Map<String, Object>{ 'recordId' => UserInfo.getUserId() }));
        Assert.isFalse(ApexAgentToolExecutor.execute(toolsByName, tc).isError(), 'Follow-up call should succeed');
        Assert.isNull(ApexAgentToolErrorContext.consume(), 'A successful call should leave no recorded trace behind');
    }

    // ─── Typed Output → the JSON the LLM receives ────────────────────────────────

    @IsTest
    static void testExecuteInlineSerializesTypedOutputs() {
        ApexAgent_Topic__c topic = ApexAgentTestDataFactory.newTopic('Executor Typed Output Topic', 'executor_typed_output');
        insert topic;

        // Nested typed lists survive, and null Output fields are dropped
        Map<String, Object> fieldDetails = executeInline('ApexAgentGetFieldDetails', new Map<String, Object>{
            'objectApiName'    => 'Lead',
            'fieldApiNameList' => new List<Object>{ 'LeadSource', 'NoSuchField__xyz' }
        });
        Assert.areEqual('Lead', fieldDetails.get('objectApiName'), 'Output fields should be at the top level');
        Assert.isFalse(fieldDetails.containsKey('message'), 'A null Output field should be suppressed');
        List<Object> fields = (List<Object>) fieldDetails.get('fields');
        Map<String, Object> picklist = (Map<String, Object>) fields[0];
        Assert.isTrue(((List<Object>) picklist.get('picklistValues')).size() > 0, 'Nested picklistValues should be serialized');
        Assert.isFalse(picklist.containsKey('lookupReferences'), 'A null field inside a nested object should be suppressed');
        Assert.areEqual(false, ((Map<String, Object>) fields[1]).get('found'), 'An unknown field should report found=false');

        // Compact string entries stay strings
        Map<String, Object> objectDetails = executeInline('ApexAgentGetObjectDetails', new Map<String, Object>{ 'objectApiName' => 'Account' });
        Map<String, Object> firstGroup = (Map<String, Object>) ((List<Object>) objectDetails.get('fields'))[0];
        Assert.isTrue(firstGroup.containsKey('soapType'), 'Each group should carry its SOAP type');
        Assert.isTrue(((List<Object>) firstGroup.get('fields'))[0] instanceof String, 'Field entries should stay compact strings');

        // SObject payloads are nested under their Output field
        Map<String, Object> recordDetails = executeInline('ApexAgentGetRecordDetails', new Map<String, Object>{ 'recordId' => String.valueOf(topic.Id) });
        Assert.areEqual('Executor Typed Output Topic', ((Map<String, Object>) recordDetails.get('record')).get('Name'), 'The record should be under record');
        Assert.isFalse(recordDetails.containsKey('found'), 'A null Output field should be suppressed');

        Map<String, Object> queried = executeInline('ApexAgentQueryRecords', new Map<String, Object>{
            'soqlQuery' => 'SELECT Id, Name FROM ApexAgent_Topic__c WHERE Id = \'' + topic.Id + '\''
        });
        Assert.areEqual(1, queried.get('recordCount'), 'recordCount should be at the top level');
        Assert.areEqual(1, ((List<Object>) queried.get('records')).size(), 'records should hold the matching record');
        Assert.isFalse(queried.containsKey('error'), 'A null Output field should be suppressed');
    }

    private static Map<String, Object> executeInline(String toolName, Map<String, Object> inputs) {
        return (Map<String, Object>) JSON.deserializeUntyped(ApexAgentToolExecutor.executeInline(toolName, inputs));
    }
}
