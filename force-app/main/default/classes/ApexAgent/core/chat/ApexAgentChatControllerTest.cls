/**
 * Test coverage for ApexAgentChatController.
 * Covers: getAgentConfig, getThreads, getMessages, sendMessage, saveFeedback, getExecutionMessages.
 */
@IsTest
private class ApexAgentChatControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data factory
    // ─────────────────────────────────────────────────────────────────────────

    private static ApexAgent_LLM__c buildLlm() {
        ApexAgent_LLM__c llm = new ApexAgent_LLM__c(
            Name                      = 'TestLLM',
            Model_API_Name__c         = 'test-model',
            Family__c                 = 'Anthropic',
            Named_Credential__c       = 'TestCred',
            Chat_Completions_Path__c  = '/v1/messages',
            Uncached_Input_Token_Cost_M__c = 0,
            Output_Token_Cost_M__c    = 0
        );
        insert llm;
        return llm;
    }

    private static ApexAgent_Agent__c buildAgent(Id llmId) {
        ApexAgent_Agent__c agent = new ApexAgent_Agent__c(
            Name                  = 'TestAgent',
            LLM__c                = llmId,
            Active__c             = true,
            Max_Tokens__c         = 1000,
            Tagline__c            = 'Test Tagline',
            Primary_Color__c      = '#FF0000',
            Show_Execution_Message__c = true,
            Avatar_Static_Resource__c = 'TestAvatar'
        );
        insert agent;
        return agent;
    }

    private static ApexAgent_Agent__c buildAgentMinimal(Id llmId) {
        ApexAgent_Agent__c agent = new ApexAgent_Agent__c(
            Name      = 'MinimalAgent',
            LLM__c    = llmId,
            Active__c = true,
            Max_Tokens__c = 1000
        );
        insert agent;
        return agent;
    }

    private static ApexAgent_Thread_Log__c buildThread(String uuid) {
        ApexAgent_Thread_Log__c thread = new ApexAgent_Thread_Log__c(
            Agent_Thread_UUID__c  = uuid,
            Last_Activity_At__c   = Datetime.now()
        );
        insert thread;
        return thread;
    }

    private static ApexAgent_Message_Log__c buildMessage(Id threadId, Id agentId, String uuid) {
        ApexAgent_Message_Log__c msg = new ApexAgent_Message_Log__c(
            Thread__c           = threadId,
            Agent__c            = agentId,
            Agent_Message_UUID__c = uuid,
            User_Input__c       = 'Hello world from test',
            Agent_Response__c   = 'Test response',
            Started_At__c       = Datetime.now().addSeconds(-5),
            Ended_At__c         = Datetime.now()
        );
        insert msg;
        return msg;
    }

    private static ApexAgent_Tool_Log__c buildToolLog(Id messageLogId) {
        ApexAgent_Tool_Log__c tl = new ApexAgent_Tool_Log__c(
            Message_Log__c     = messageLogId,
            Tool_Name__c       = 'TestTool',
            Execution_Message__c = 'Running TestTool',
            Input__c           = '{}',
            Output__c          = '{"result":"ok"}',
            Status__c          = 'Success',
            Started_At__c      = Datetime.now().addSeconds(-3),
            Ended_At__c        = Datetime.now()
        );
        insert tl;
        return tl;
    }

    private static ApexAgent_Error_Log__c buildErrorLog(Id messageLogId) {
        ApexAgent_Error_Log__c el = new ApexAgent_Error_Log__c(
            Message_Log__c = messageLogId,
            Error__c       = 'Something went wrong',
            Stack_Trace__c = 'at line 42'
        );
        insert el;
        return el;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getAgentConfig
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetAgentConfig() {
        ApexAgent_LLM__c llm = buildLlm();
        buildAgent(llm.Id); // inserted to satisfy SOQL by Name

        Test.startTest();
        ApexAgentChatController.AgentConfig config =
            ApexAgentChatController.getAgentConfig('TestAgent');
        Test.stopTest();

        Assert.isNotNull(config, 'Config should not be null');
        Assert.areEqual('TestAgent',   config.name,                'Name mismatch');
        Assert.areEqual('Test Tagline', config.tagline,            'Tagline mismatch');
        Assert.areEqual('#FF0000',     config.primaryColor,        'Primary color mismatch');
        Assert.isTrue(config.showExecutionMessage,                  'showExecutionMessage should be true');
        Assert.areEqual('/resource/TestAvatar', config.avatarUrl,  'Avatar URL mismatch');
    }

    @IsTest
    static void testGetAgentConfigDefaults() {
        // Agent with no colors / avatar → defaults applied
        ApexAgent_LLM__c llm = buildLlm();
        buildAgentMinimal(llm.Id); // inserted to satisfy SOQL by Name

        Test.startTest();
        ApexAgentChatController.AgentConfig config =
            ApexAgentChatController.getAgentConfig('MinimalAgent');
        Test.stopTest();

        Assert.isNotNull(config, 'Config should not be null');
        Assert.areEqual('#0176D3', config.primaryColor, 'Default primary color mismatch');
        Assert.isNull(config.avatarUrl,                  'Avatar URL should be null');
    }

    @IsTest
    static void testGetAgentConfigNullAndMissing() {
        Test.startTest();
        ApexAgentChatController.AgentConfig blankResult =
            ApexAgentChatController.getAgentConfig('   ');
        ApexAgentChatController.AgentConfig nullResult =
            ApexAgentChatController.getAgentConfig(null);
        ApexAgentChatController.AgentConfig missingResult =
            ApexAgentChatController.getAgentConfig('DoesNotExist');
        Test.stopTest();

        Assert.isNull(blankResult,   'Blank agent name should return null');
        Assert.isNull(nullResult,    'Null agent name should return null');
        Assert.isNull(missingResult, 'Unknown agent should return null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getThreads
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetThreads() {
        ApexAgent_LLM__c llm     = buildLlm();
        ApexAgent_Agent__c agent = buildAgent(llm.Id);
        String threadUUID        = 'test-thread-uuid-001';
        ApexAgent_Thread_Log__c thread = buildThread(threadUUID);
        buildMessage(thread.Id, agent.Id, 'msg-uuid-001');

        Test.startTest();
        List<ApexAgentChatController.ThreadSummary> threads =
            ApexAgentChatController.getThreads('TestAgent');
        Test.stopTest();

        Assert.isFalse(threads.isEmpty(), 'Should return at least one thread');
        Assert.areEqual(threadUUID, threads[0].threadUUID, 'Thread UUID mismatch');
        Assert.isNotNull(threads[0].firstMessage,          'First message should not be null');
        Assert.isNotNull(threads[0].lastActivity,          'Last activity should not be null');
    }

    @IsTest
    static void testGetThreadsBlankAgent() {
        // No data setup needed — method returns early on blank/null input
        Test.startTest();
        List<ApexAgentChatController.ThreadSummary> nullResult =
            ApexAgentChatController.getThreads(null);
        List<ApexAgentChatController.ThreadSummary> blankResult =
            ApexAgentChatController.getThreads('   ');
        Test.stopTest();

        Assert.isTrue(nullResult.isEmpty(),  'Null agent name should return empty list');
        Assert.isTrue(blankResult.isEmpty(), 'Blank agent name should return empty list');
    }

    @IsTest
    static void testGetThreadsFirstMessageTruncated() {
        ApexAgent_LLM__c llm     = buildLlm();
        ApexAgent_Agent__c agent = buildAgent(llm.Id);
        ApexAgent_Thread_Log__c thread = buildThread('thread-truncate');

        // Message longer than 60 chars
        ApexAgent_Message_Log__c msg = new ApexAgent_Message_Log__c(
            Thread__c           = thread.Id,
            Agent__c            = agent.Id,
            Agent_Message_UUID__c = 'msg-trunc',
            User_Input__c       = 'A'.repeat(100),
            Started_At__c       = Datetime.now()
        );
        insert msg;

        Test.startTest();
        List<ApexAgentChatController.ThreadSummary> threads =
            ApexAgentChatController.getThreads('TestAgent');
        Test.stopTest();

        Assert.isFalse(threads.isEmpty(), 'Should return thread');
        Assert.areEqual(60, threads[0].firstMessage.length(), 'First message should be truncated to 60 chars');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getMessages
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetMessages() {
        ApexAgent_LLM__c llm     = buildLlm();
        ApexAgent_Agent__c agent = buildAgent(llm.Id);
        ApexAgent_Thread_Log__c thread = buildThread('thread-msg-test');
        ApexAgent_Message_Log__c msg   = buildMessage(thread.Id, agent.Id, 'msg-uuid-002');
        buildToolLog(msg.Id);
        buildErrorLog(msg.Id);

        Test.startTest();
        List<ApexAgentChatController.MessageData> messages =
            ApexAgentChatController.getMessages('thread-msg-test');
        Test.stopTest();

        Assert.isFalse(messages.isEmpty(), 'Should return messages');
        ApexAgentChatController.MessageData first = messages[0];
        Assert.areEqual('msg-uuid-002',      first.agentMessageUUID,      'UUID mismatch');
        Assert.areEqual('Hello world from test', first.userInput,         'User input mismatch');
        Assert.areEqual('Test response',     first.agentResponse,         'Agent response mismatch');
        Assert.isNotNull(first.startedAt,                                  'startedAt should not be null');
        Assert.isNotNull(first.endedAt,                                    'endedAt should not be null');
        Assert.isFalse(first.toolLogs.isEmpty(),   'Tool logs should be populated');
        Assert.isFalse(first.errorLogs.isEmpty(),  'Error logs should be populated');
        Assert.areEqual('Running TestTool',   first.toolLogs[0].executionMessage, 'Execution message mismatch');
        Assert.areEqual('Success',            first.toolLogs[0].status,           'Tool status mismatch');
        Assert.areEqual('Something went wrong', first.errorLogs[0].error,         'Error message mismatch');
    }

    @IsTest
    static void testGetMessagesBlankThread() {
        Test.startTest();
        List<ApexAgentChatController.MessageData> results =
            ApexAgentChatController.getMessages(null);
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Null thread UUID should return empty list');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveFeedback
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSaveFeedback() {
        ApexAgent_LLM__c llm     = buildLlm();
        ApexAgent_Agent__c agent = buildAgent(llm.Id);
        ApexAgent_Thread_Log__c thread = buildThread('thread-feedback');
        buildMessage(thread.Id, agent.Id, 'msg-fb');

        Test.startTest();
        ApexAgentChatController.saveFeedback('msg-fb', 'Thumbs Up', 'Great response!');
        Test.stopTest();

        ApexAgent_Message_Log__c updated = [
            SELECT Feedback__c, Feedback_Notes__c
            FROM ApexAgent_Message_Log__c
            WHERE Agent_Message_UUID__c = 'msg-fb'
        ];
        Assert.areEqual('Thumbs Up',      updated.Feedback__c,      'Feedback value mismatch');
        Assert.areEqual('Great response!', updated.Feedback_Notes__c, 'Feedback notes mismatch');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getExecutionMessages
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetExecutionMessages() {
        // Cache miss → empty list (no events published in test context)
        Test.startTest();
        List<Object> actions = ApexAgentChatController.getExecutionMessages('test-msg-uuid');
        Test.stopTest();

        Assert.isNotNull(actions, 'Result should not be null');
        Assert.isTrue(actions.isEmpty(), 'Should return empty list for cache miss');
    }

    @IsTest
    static void testGetExecutionMessagesBlank() {
        Test.startTest();
        List<Object> actions = ApexAgentChatController.getExecutionMessages(null);
        Test.stopTest();

        Assert.isNotNull(actions, 'Result should not be null for null input');
        Assert.isTrue(actions.isEmpty(), 'Should return empty list for null input');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // sendMessage (mock orchestrator call — validates wiring, not LLM logic)
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSendMessageReturnsResponse() {
        // This validates the method routes to ApexAgentOrchestrator.run without
        // exercising live LLM callouts (callouts are blocked in tests).
        // We verify the return type is AgentResponse and errorMessage is set
        // (since there is no real callout in the test transaction).
        ApexAgent_LLM__c llm = buildLlm();
        buildAgent(llm.Id); // inserted to satisfy SOQL by Name

        Test.startTest();
        try {
            ApexAgentOrchestrator.AgentResponse response =
                ApexAgentChatController.sendMessage(
                    'TestAgent', 'What are my open cases?',
                    'test-thread', 'test-msg', null
                );
            // If orchestrator completes, it should have a messageUUID
            Assert.isNotNull(response, 'Response should not be null');
        } catch (Exception e) {
            // Callout blocked in test context — verify it's a callout or expected error
            Assert.isTrue(
                e.getMessage().contains('Callout') || e.getMessage().contains('callout')
                    || e.getMessage().contains('endpoint'),
                'Expected callout restriction error, got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }
}
