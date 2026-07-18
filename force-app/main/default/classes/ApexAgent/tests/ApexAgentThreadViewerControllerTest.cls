@IsTest
private class ApexAgentThreadViewerControllerTest {

    @TestSetup
    static void makeData() {
        ApexAgent_Thread_Log__c thread = new ApexAgent_Thread_Log__c(
            Agent_Thread_UUID__c = 'test-thread-uuid-viewer-001',
            Started_At__c        = Datetime.now().addMinutes(-10)
        );
        insert thread;

        ApexAgent_Message_Log__c msg1 = new ApexAgent_Message_Log__c(
            Thread__c       = thread.Id,
            User_Input__c   = 'What is Apex?',
            Agent_Response__c = 'Apex is a strongly typed, object-oriented programming language.',
            Started_At__c   = Datetime.now().addMinutes(-9),
            Ended_At__c     = Datetime.now().addMinutes(-8),
            Duration_ms__c  = 3200,
            Cost__c         = 0.00123
        );
        ApexAgent_Message_Log__c msg2 = new ApexAgent_Message_Log__c(
            Thread__c       = thread.Id,
            User_Input__c   = 'Tell me more.',
            Started_At__c   = Datetime.now().addMinutes(-5)
        );
        insert new List<ApexAgent_Message_Log__c>{ msg1, msg2 };

        insert new List<ApexAgent_Tool_Log__c>{
            new ApexAgent_Tool_Log__c(Message_Log__c = msg1.Id),
            new ApexAgent_Tool_Log__c(Message_Log__c = msg1.Id)
        };
    }

    @IsTest
    static void testGetThreadMessages_returnsCorrectData() {
        ApexAgent_Thread_Log__c thread = [SELECT Id FROM ApexAgent_Thread_Log__c LIMIT 1];

        Test.startTest();
        List<ApexAgentThreadViewerController.MessageWrapper> result =
            ApexAgentThreadViewerController.getThreadMessages(thread.Id);
        Test.stopTest();

        Assert.areEqual(2, result.size(), 'Should return both messages ordered by Started_At__c');

        ApexAgentThreadViewerController.MessageWrapper first = result[0];
        Assert.areEqual('What is Apex?', first.userInput, 'First message userInput should match');
        Assert.isNotNull(first.agentResponse, 'First message should have an agent response');
        Assert.areEqual(2, first.toolCallCount, 'First message should show 2 tool calls');
        Assert.isNotNull(first.cost, 'First message should have cost');
        Assert.isNotNull(first.durationMs, 'First message should have durationMs');
        Assert.isNotNull(first.startedAt, 'startedAt should be populated');
        Assert.isNotNull(first.endedAt, 'endedAt should be populated');

        ApexAgentThreadViewerController.MessageWrapper second = result[1];
        Assert.areEqual('Tell me more.', second.userInput, 'Second message userInput should match');
        Assert.isNull(second.agentResponse, 'Second message should have no response yet');
        Assert.areEqual(0, second.toolCallCount, 'Second message should have 0 tool calls');
    }

    @IsTest
    static void testGetThreadMessages_capsAtMostRecentAndPreservesChronologicalOrder() {
        ApexAgent_Thread_Log__c thread = new ApexAgent_Thread_Log__c(
            Agent_Thread_UUID__c = 'test-thread-uuid-viewer-bulk',
            Started_At__c        = Datetime.now().addHours(-2)
        );
        insert thread;

        // 105 messages, oldest first — exceeds the 100-message cap, so the oldest 5
        // must be dropped while the most recent 100 remain in chronological order.
        List<ApexAgent_Message_Log__c> messages = new List<ApexAgent_Message_Log__c>();
        for (Integer i = 0; i < 105; i++) {
            messages.add(new ApexAgent_Message_Log__c(
                Thread__c     = thread.Id,
                User_Input__c = 'Message ' + i,
                Started_At__c = Datetime.now().addHours(-2).addMinutes(i)
            ));
        }
        insert messages;

        Test.startTest();
        List<ApexAgentThreadViewerController.MessageWrapper> result =
            ApexAgentThreadViewerController.getThreadMessages(thread.Id);
        Test.stopTest();

        Assert.areEqual(100, result.size(), 'Should cap at the 100 most recent messages');
        Assert.areEqual('Message 5',   result[0].userInput,  'Oldest 5 messages should be dropped');
        Assert.areEqual('Message 104', result[99].userInput, 'Most recent message should be last (chronological order)');
    }

    @IsTest
    static void testGetThreadMessages_emptyAndNullCases() {
        ApexAgent_Thread_Log__c emptyThread = new ApexAgent_Thread_Log__c(
            Agent_Thread_UUID__c = 'test-thread-uuid-viewer-002'
        );
        insert emptyThread;

        Test.startTest();
        List<ApexAgentThreadViewerController.MessageWrapper> emptyResult =
            ApexAgentThreadViewerController.getThreadMessages(emptyThread.Id);
        List<ApexAgentThreadViewerController.MessageWrapper> nullResult =
            ApexAgentThreadViewerController.getThreadMessages(null);
        Test.stopTest();

        Assert.areEqual(0, emptyResult.size(), 'Thread with no messages should return empty list');
        Assert.areEqual(0, nullResult.size(), 'Null threadId should return empty list');
    }
}
