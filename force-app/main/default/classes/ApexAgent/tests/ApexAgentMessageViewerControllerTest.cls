@IsTest
private class ApexAgentMessageViewerControllerTest {

    @TestSetup
    static void makeData() {
        ApexAgent_Thread_Log__c thread = new ApexAgent_Thread_Log__c(
            Agent_Thread_UUID__c = 'test-thread-uuid-msg-viewer-001',
            Started_At__c        = Datetime.now().addMinutes(-10)
        );
        insert thread;

        ApexAgent_Message_Log__c msg = new ApexAgent_Message_Log__c(
            Thread__c              = thread.Id,
            User_Input__c          = 'List my open cases',
            Agent_Response__c      = '<p>You have <b>3</b> open cases.</p>',
            Started_At__c          = Datetime.now().addMinutes(-9),
            Ended_At__c            = Datetime.now().addMinutes(-8),
            Duration_ms__c         = 4200,
            Cost__c                = 0.0042,
            Model_Name__c          = 'gpt-test',
            Input_Tokens__c        = 2500,
            Output_Tokens__c       = 180,
            Cached_Input_Tokens__c = 1024,
            Reasoning_Tokens__c    = 64,
            Feedback__c            = 'Thumbs Down',
            Feedback_Notes__c      = 'Missed a case'
        );
        insert msg;

        insert new List<ApexAgent_Tool_Log__c>{
            new ApexAgent_Tool_Log__c(Message_Log__c = msg.Id, Execution_Message__c = 'Queried Case', Status__c = 'Success'),
            new ApexAgent_Tool_Log__c(Message_Log__c = msg.Id, Execution_Message__c = 'Queried Account', Status__c = 'Success')
        };
        insert new ApexAgent_Error_Log__c(Message_Log__c = msg.Id, Error__c = 'Tool timed out');
    }

    @IsTest
    static void testGetMessage_returnsFullMessage() {
        ApexAgent_Message_Log__c msg = [SELECT Id FROM ApexAgent_Message_Log__c LIMIT 1];

        Test.startTest();
        ApexAgentConversationLogService.MessageWrapper result = ApexAgentMessageViewerController.getMessage(msg.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Existing message should be returned');
        Assert.areEqual(String.valueOf(msg.Id), result.id, 'id should match the record');
        Assert.areEqual('List my open cases', result.userInput, 'userInput should match');
        Assert.areEqual('<p>You have <b>3</b> open cases.</p>', result.agentResponse, 'agentResponse should keep rich text');
        Assert.areEqual('gpt-test', result.modelName, 'modelName should match');
        Assert.areEqual(2500, result.inputTokens, 'inputTokens should match');
        Assert.areEqual(180, result.outputTokens, 'outputTokens should match');
        Assert.areEqual(1024, result.cachedInputTokens, 'cachedInputTokens should match');
        Assert.areEqual(64, result.reasoningTokens, 'reasoningTokens should match');
        Assert.areEqual(4200, result.durationMs, 'durationMs should match');
        Assert.areEqual(0.0042, result.cost, 'cost should match');
        Assert.areEqual('Thumbs Down', result.feedback, 'feedback should match');
        Assert.areEqual('Missed a case', result.feedbackNotes, 'feedbackNotes should match');
        Assert.areEqual(2, result.toolCallCount, 'Both tool logs should be counted');
        Assert.areEqual('Queried Case', result.toolLogs[0].executionMessage, 'Tool logs should be in creation order');
        Assert.areEqual(1, result.errorLogs.size(), 'Error log should be included');
        Assert.areEqual('Tool timed out', result.errorLogs[0].error, 'Error text should match');
    }

    @IsTest
    static void testGetMessage_nullAndMissingIds() {
        ApexAgent_Message_Log__c msg = [SELECT Id FROM ApexAgent_Message_Log__c LIMIT 1];
        delete msg;

        Test.startTest();
        ApexAgentConversationLogService.MessageWrapper nullResult    = ApexAgentMessageViewerController.getMessage(null);
        ApexAgentConversationLogService.MessageWrapper missingResult = ApexAgentMessageViewerController.getMessage(msg.Id);
        Test.stopTest();

        Assert.isNull(nullResult, 'Null Id should return null');
        Assert.isNull(missingResult, 'Deleted message should return null');
    }
}
