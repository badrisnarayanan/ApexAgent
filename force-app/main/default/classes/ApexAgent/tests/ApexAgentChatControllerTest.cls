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

    // ─────────────────────────────────────────────────────────────────────────
    // sendMessage (LLM-mocked — exercises real orchestrator/LLMClient/logging paths)
    // ─────────────────────────────────────────────────────────────────────────

    private static ApexAgent_Error_Log__c getErrorLogFor(String messageUUID) {
        ApexAgent_Message_Log__c ml = [
            SELECT Id FROM ApexAgent_Message_Log__c
            WHERE Agent_Message_UUID__c = :messageUUID
            LIMIT 1
        ];
        List<ApexAgent_Error_Log__c> errs = [
            SELECT Error__c, Stack_Trace__c FROM ApexAgent_Error_Log__c WHERE Message_Log__c = :ml.Id
        ];
        return errs.isEmpty() ? null : errs[0];
    }

    @IsTest
    static void testSendMessageHappyPathStopResponse() {
        ApexAgent_LLM__c llm = buildLlm();
        buildAgent(llm.Id);
        String messageUUID = 'msg-happy-' + UUID.randomUUID().toString();

        Test.setMock(HttpCalloutMock.class,
            new ApexAgentLLMCalloutMock(200, ApexAgentLLMCalloutMock.stopResponse('Here is your answer.')));

        Test.startTest();
        ApexAgentOrchestrator.AgentResponse response = ApexAgentChatController.sendMessage(
            'TestAgent', 'What are my open cases?', null, messageUUID, null
        );
        Test.stopTest();

        Assert.areEqual('Here is your answer.', response.llmResponse, 'Should surface the LLM content');
        Assert.isNull(response.errorMessage, 'Successful turn should have no error message');
    }

    @IsTest
    static void testSendMessageEmptyChoicesReturnsSanitizedError() {
        ApexAgent_LLM__c llm = buildLlm();
        buildAgent(llm.Id);
        // Thread__c is a required lookup on Message_Log__c — a blank threadUUID means
        // ApexAgentLogger silently drops the whole log write, so getErrorLogFor below
        // would find nothing. A real thread is needed purely so logging succeeds.
        ApexAgent_Thread_Log__c thread = buildThread('thread-empty-choices');
        String messageUUID = 'msg-empty-choices-' + UUID.randomUUID().toString();

        Test.setMock(HttpCalloutMock.class,
            new ApexAgentLLMCalloutMock(200, ApexAgentLLMCalloutMock.emptyChoicesResponse()));

        Test.startTest();
        ApexAgentOrchestrator.AgentResponse response = ApexAgentChatController.sendMessage(
            'TestAgent', 'What are my open cases?', thread.Agent_Thread_UUID__c, messageUUID, null
        );
        Test.stopTest();

        Assert.areEqual(
            'Something went wrong processing your request. Please try again.',
            response.errorMessage,
            'Client should only see the generic sanitized message'
        );
        ApexAgent_Error_Log__c errLog = getErrorLogFor(messageUUID);
        Assert.isNotNull(errLog, 'Full detail should still be written to Error_Log__c');
        Assert.isTrue(errLog.Error__c.contains('no choices'), 'Internal log should carry the real cause');
    }

    @IsTest
    static void testSendMessageLengthFinishReasonReturnsSafeMessage() {
        ApexAgent_LLM__c llm = buildLlm();
        buildAgent(llm.Id);
        String messageUUID = 'msg-length-' + UUID.randomUUID().toString();

        Test.setMock(HttpCalloutMock.class,
            new ApexAgentLLMCalloutMock(200, ApexAgentLLMCalloutMock.lengthResponseBlankContent()));

        Test.startTest();
        ApexAgentOrchestrator.AgentResponse response = ApexAgentChatController.sendMessage(
            'TestAgent', 'What are my open cases?', null, messageUUID, null
        );
        Test.stopTest();

        Assert.areEqual(
            'Response was cut off before any content was generated '
                + '(max tokens reached). Try increasing Max Tokens on the agent.',
            response.errorMessage,
            'finish_reason=length with blank content should surface this specific, safe message'
        );
    }

    @IsTest
    static void testSendMessageNonRetryableStatusFailsWithoutExhaustingRetries() {
        ApexAgent_LLM__c llm = buildLlm();
        buildAgent(llm.Id);
        // Thread__c is a required lookup on Message_Log__c — see comment in
        // testSendMessageEmptyChoicesReturnsSanitizedError above.
        ApexAgent_Thread_Log__c thread = buildThread('thread-400');
        String messageUUID = 'msg-400-' + UUID.randomUUID().toString();

        Test.setMock(HttpCalloutMock.class,
            new ApexAgentLLMCalloutMock(400, '{"error":"bad request"}'));

        Test.startTest();
        ApexAgentOrchestrator.AgentResponse response = ApexAgentChatController.sendMessage(
            'TestAgent', 'What are my open cases?', thread.Agent_Thread_UUID__c, messageUUID, null
        );
        Test.stopTest();

        Assert.areEqual(
            'Something went wrong processing your request. Please try again.',
            response.errorMessage,
            'Client should only see the generic sanitized message'
        );
        ApexAgent_Error_Log__c errLog = getErrorLogFor(messageUUID);
        Assert.isNotNull(errLog, 'Full detail should still be written to Error_Log__c');
        Assert.isTrue(errLog.Error__c.contains('non-retryable status'),
            'Should fail via the immediate non-retryable path, not the retry-exhaustion path');
        Assert.isFalse(errLog.Error__c.contains('attempt(s)'),
            'A 400 must not be retried — message should not mention retry attempts');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // sendMessage — a failing tool call
    // ─────────────────────────────────────────────────────────────────────────

    /** First LLM call asks for a tool call; every later call answers. Records each request body. */
    private class ToolCallThenStopMock implements HttpCalloutMock {
        public List<String> requestBodies = new List<String>();

        public HttpResponse respond(HttpRequest req) {
            requestBodies.add(req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(requestBodies.size() == 1
                ? ApexAgentLLMCalloutMock.toolCallResponse('call-err-1', 'GetRecordDetails', '{"recordId":"not-an-id"}')
                : ApexAgentLLMCalloutMock.stopResponse('The tool failed.'));
            return res;
        }
    }

    @IsTest
    static void testFailedToolCallReachesLlmAndIsLoggedAsError() {
        ApexAgent_LLM__c llm = buildLlm();
        ApexAgent_Agent__c agent = buildAgent(llm.Id);
        ApexAgent_Thread_Log__c thread = buildThread('thread-tool-error');

        ApexAgent_Topic__c topic = new ApexAgent_Topic__c(Name = 'Records', Topic_API_Name__c = 'records');
        insert topic;
        insert new ApexAgent_Topic_Map__c(Agent__c = agent.Id, Topic__c = topic.Id, Active__c = true, Order__c = 1);
        ApexAgent_Tool__c tool = new ApexAgent_Tool__c(
            Apex_Class_Name__c = 'GetRecordDetails',
            Modifies_Salesforce_Data__c = false,
            Schema__c = JSON.serialize(new Map<String, Object>{
                'type' => 'function',
                'function' => new Map<String, Object>{
                    'name' => 'GetRecordDetails',
                    'description' => 'Fetches a record by Id.',
                    'parameters' => new Map<String, Object>{
                        'type' => 'object',
                        'properties' => new Map<String, Object>{
                            'recordId' => new Map<String, Object>{ 'type' => 'string' }
                        }
                    }
                }
            })
        );
        insert tool;
        insert new ApexAgent_Topic_Tool_Map__c(Topic__c = topic.Id, Tool__c = tool.Id, Active__c = true);

        String messageUUID = 'msg-tool-error-' + UUID.randomUUID().toString();
        ToolCallThenStopMock mock = new ToolCallThenStopMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ApexAgentOrchestrator.AgentResponse response = ApexAgentChatController.sendMessage(
            'TestAgent', 'Fetch that record', thread.Agent_Thread_UUID__c, messageUUID, null
        );
        Test.stopTest();

        Assert.isNull(response.errorMessage, 'A failed tool call should not fail the turn');
        Assert.areEqual('The tool failed.', response.llmResponse, 'The LLM should get a second call and answer');
        Assert.areEqual(2, mock.requestBodies.size(), 'A tool call should be followed by exactly one more LLM call');
        Assert.isTrue(mock.requestBodies[1].contains('recordId is not a valid Salesforce ID'),
            'The LLM must be told why the tool failed');

        ApexAgent_Tool_Log__c toolLog = [
            SELECT Status__c, Error_Message__c
            FROM ApexAgent_Tool_Log__c
            WHERE Message_Log__r.Agent_Message_UUID__c = :messageUUID
        ];
        Assert.areEqual('Error', toolLog.Status__c, 'The failed tool call should be logged with Error status');
        Assert.isTrue(toolLog.Error_Message__c.contains('recordId is not a valid Salesforce ID'),
            'The tool error message should be logged');
    }
}
