/**
 * Exercises the ApexAgent_Tool_Execution__e trigger end-to-end: publishing an
 * event should reach ApexAgentExecutionMessageHandler.handleEvents via
 * ApexAgentToolExecutionEventTrigger, land in Platform Cache, and be
 * readable back through the AuraEnabled poll method.
 */
@IsTest
private class ApexAgentExecutionMessageHandlerTest {

    @IsTest
    static void testInProgressThenCompletedEventsMergeInCache() {
        String messageUUID = 'msg-exec-' + UUID.randomUUID().toString();

        Test.startTest();
        EventBus.publish(new ApexAgent_Tool_Execution__e(
            Message_UUID__c      = messageUUID,
            Tool_Call_Id__c      = 'call-1',
            Tool_Name__c         = 'SearchRecords',
            Execution_Message__c = 'Searching for account records',
            Status__c             = 'In Progress'
        ));
        Test.stopTest();

        List<Map<String, Object>> actions = ApexAgentExecutionMessageHandler.getToolActions(messageUUID);
        Assert.areEqual(1, actions.size(), 'One tool action should be cached');
        Assert.areEqual('call-1', actions[0].get('toolCallId'), 'Tool call id mismatch');
        Assert.areEqual('SearchRecords', actions[0].get('toolName'), 'Tool name mismatch');
        Assert.areEqual('Searching for account records', actions[0].get('executionMessage'), 'Execution message mismatch');
        Assert.areEqual('In Progress', actions[0].get('status'), 'Status mismatch');
    }

    @IsTest
    static void testCompletedEventPreservesExecutionMessageAndToolName() {
        String messageUUID = 'msg-exec-' + UUID.randomUUID().toString();

        Test.startTest();
        EventBus.publish(new ApexAgent_Tool_Execution__e(
            Message_UUID__c      = messageUUID,
            Tool_Call_Id__c      = 'call-2',
            Tool_Name__c         = 'QueryRecords',
            Execution_Message__c = 'Querying open cases',
            Status__c             = 'In Progress'
        ));
        EventBus.publish(new ApexAgent_Tool_Execution__e(
            Message_UUID__c = messageUUID,
            Tool_Call_Id__c = 'call-2',
            Status__c        = 'Completed'
        ));
        Test.stopTest();

        List<Map<String, Object>> actions = ApexAgentExecutionMessageHandler.getToolActions(messageUUID);
        Assert.areEqual(1, actions.size(), 'Completed event should merge into the existing entry, not duplicate it');
        Assert.areEqual('Completed', actions[0].get('status'), 'Status should update to Completed');
        Assert.areEqual('Querying open cases', actions[0].get('executionMessage'), 'Execution message from the In Progress event should be preserved');
        Assert.areEqual('QueryRecords', actions[0].get('toolName'), 'Tool name from the In Progress event should be preserved');
    }

    @IsTest
    static void testGetToolActionsBlankAndCacheMiss() {
        Assert.isTrue(ApexAgentExecutionMessageHandler.getToolActions(null).isEmpty(), 'Null messageUUID should return empty list');
        Assert.isTrue(ApexAgentExecutionMessageHandler.getToolActions('never-published').isEmpty(), 'Cache miss should return empty list');
    }
}
