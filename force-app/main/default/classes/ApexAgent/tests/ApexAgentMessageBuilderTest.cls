@IsTest
private class ApexAgentMessageBuilderTest {

    @IsTest
    static void testThreadHistoryReplaysToolOutputAndToolErrors() {
        ApexAgent_Thread_Log__c thread = new ApexAgent_Thread_Log__c(
            Agent_Thread_UUID__c = 'thread-history-test',
            Last_Activity_At__c  = Datetime.now()
        );
        insert thread;
        ApexAgent_Message_Log__c msg = new ApexAgent_Message_Log__c(
            Thread__c             = thread.Id,
            Agent_Message_UUID__c = 'msg-history-test',
            User_Input__c         = 'Look these up',
            Agent_Response__c     = 'Done'
        );
        insert msg;
        // Inserted in the opposite order to their start times, so replay order must come from Started_At__c.
        Datetime firstStart = Datetime.now().addSeconds(-30);
        insert new List<ApexAgent_Tool_Log__c>{
            new ApexAgent_Tool_Log__c(
                Message_Log__c = msg.Id, Tool_Call_Id__c = 'call-ok', Tool_Name__c = 'GetObjectApiName',
                Input__c = '{"recordId":"001000000000000AAA"}', Output__c = '{"objectApiName":"Account"}', Status__c = 'Success',
                Started_At__c = firstStart.addSeconds(20)
            ),
            new ApexAgent_Tool_Log__c(
                Message_Log__c = msg.Id, Tool_Call_Id__c = 'call-failed', Tool_Name__c = 'GetRecordDetails',
                Input__c = '{"recordId":"not-an-id"}', Error_Message__c = 'recordId is not a valid Salesforce ID: not-an-id', Status__c = 'Error',
                Started_At__c = firstStart.addSeconds(10)
            ),
            new ApexAgent_Tool_Log__c(
                Message_Log__c = msg.Id, Tool_Call_Id__c = 'call-blank', Tool_Name__c = 'GetObjectApiName',
                Input__c = '{}', Status__c = 'Success',
                Started_At__c = firstStart
            )
        };

        List<ApexAgentApiTypes.ChatMessage> history = ApexAgentMessageBuilder.buildThreadHistory(
            'thread-history-test', 5, 5, 'Anthropic'
        );

        Map<String, String> contentByToolCallId = new Map<String, String>();
        List<String> replayedToolCallOrder = new List<String>();
        List<String> toolResultOrder = new List<String>();
        for (ApexAgentApiTypes.ChatMessage m : history) {
            if (m.role == 'tool') {
                contentByToolCallId.put(m.tool_call_id, m.content);
                toolResultOrder.add(m.tool_call_id);
            }
            if (m.role == 'assistant' && m.tool_calls != null) {
                for (ApexAgentApiTypes.ToolCall tc : m.tool_calls) {
                    replayedToolCallOrder.add(tc.id);
                }
            }
        }
        List<String> expectedOrder = new List<String>{ 'call-blank', 'call-failed', 'call-ok' };
        Assert.areEqual(expectedOrder, replayedToolCallOrder, 'Tool calls should replay in the order they started');
        Assert.areEqual(expectedOrder, toolResultOrder, 'Tool results should replay in the same order as their calls');
        Assert.areEqual(3, contentByToolCallId.size(), 'Every logged tool call should be replayed');
        Assert.areEqual('{"objectApiName":"Account"}', contentByToolCallId.get('call-ok'), 'A successful call should replay its output');
        Assert.areEqual('recordId is not a valid Salesforce ID: not-an-id', contentByToolCallId.get('call-failed'),
            'A failed call should replay its error message');
        Assert.areEqual('', contentByToolCallId.get('call-blank'), 'A call with neither output nor error should replay as empty');
    }
}
