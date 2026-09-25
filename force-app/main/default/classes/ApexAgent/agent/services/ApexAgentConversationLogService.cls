/**
 * Reads message logs (with their tool and error logs) into the view shape shared by
 * the thread viewer and message viewer LWCs.
 */
public with sharing class ApexAgentConversationLogService {

    // Shared by the thread and single-message queries so both viewers always receive
    // the same fields. Constant, bind-only — no user input is concatenated.
    private static final String MESSAGE_SELECT =
        'SELECT Id, User_Input__c, Agent_Response__c, Agent__r.Name, Agent__r.Primary_Color__c, ' +
        'Agent__r.Avatar_Static_Resource__c, Started_At__c, Ended_At__c, Duration_ms__c, Cost__c, ' +
        'Model_Name__c, Input_Tokens__c, Output_Tokens__c, Cached_Input_Tokens__c, Reasoning_Tokens__c, ' +
        'CreatedBy.Name, Feedback__c, Feedback_Notes__c, ' +
        '(SELECT Id, Execution_Message__c, Status__c FROM Tool_Logs__r ORDER BY CreatedDate ASC), ' +
        '(SELECT Error__c, Stack_Trace__c FROM Error_Logs__r ORDER BY CreatedDate ASC) ' +
        'FROM ApexAgent_Message_Log__c ';

    public class ToolLogWrapper {
        @AuraEnabled public String executionMessage;
        @AuraEnabled public String status;
    }

    public class ErrorLogWrapper {
        @AuraEnabled public String error;
        @AuraEnabled public String stackTrace;
    }

    public class MessageWrapper {
        @AuraEnabled public String             id;
        @AuraEnabled public String             userInput;
        @AuraEnabled public String             agentResponse;
        @AuraEnabled public String             agentName;
        @AuraEnabled public Datetime           startedAt;
        @AuraEnabled public Datetime           endedAt;
        @AuraEnabled public Long               durationMs;
        @AuraEnabled public Decimal            cost;
        @AuraEnabled public String             modelName;
        @AuraEnabled public Long               inputTokens;
        @AuraEnabled public Long               outputTokens;
        @AuraEnabled public Long               cachedInputTokens;
        @AuraEnabled public Long               reasoningTokens;
        @AuraEnabled public Integer            toolCallCount;
        @AuraEnabled public List<ToolLogWrapper>   toolLogs;
        @AuraEnabled public List<ErrorLogWrapper>  errorLogs;
        @AuraEnabled public String             userName;
        @AuraEnabled public String             agentPrimaryColor;
        @AuraEnabled public String             agentAvatarUrl;
        @AuraEnabled public String             feedback;
        @AuraEnabled public String             feedbackNotes;
    }

    /**
     * Returns the most recent {@code maxMessages} messages of a thread in chronological
     * (oldest-first) order.
     */
    public static List<MessageWrapper> getThreadMessages(Id threadId, Integer maxMessages) {
        List<MessageWrapper> result = new List<MessageWrapper>();
        if (threadId == null) {
            return result;
        }
        List<ApexAgent_Message_Log__c> messages = Database.queryWithBinds(
            MESSAGE_SELECT +
            'WHERE Thread__c = :threadId ORDER BY Started_At__c DESC NULLS LAST LIMIT :maxMessages',
            new Map<String, Object>{ 'threadId' => threadId, 'maxMessages' => maxMessages },
            AccessLevel.USER_MODE
        );
        // Query orders DESC to pick the most recent rows; reverse so callers still
        // receive chronological order.
        for (Integer i = messages.size() - 1; i >= 0; i--) {
            result.add(toWrapper(messages[i]));
        }
        return result;
    }

    /**
     * Returns a single message, or null when the Id is null or the record is not visible.
     */
    public static MessageWrapper getMessage(Id messageId) {
        if (messageId == null) {
            return null;
        }
        List<ApexAgent_Message_Log__c> messages = Database.queryWithBinds(
            MESSAGE_SELECT + 'WHERE Id = :messageId LIMIT 1',
            new Map<String, Object>{ 'messageId' => messageId },
            AccessLevel.USER_MODE
        );
        return messages.isEmpty() ? null : toWrapper(messages[0]);
    }

    private static MessageWrapper toWrapper(ApexAgent_Message_Log__c msg) {
        MessageWrapper w  = new MessageWrapper();
        w.id              = msg.Id;
        w.userInput       = msg.User_Input__c;
        w.agentResponse   = msg.Agent_Response__c;
        w.agentName           = msg.Agent__r != null ? msg.Agent__r.Name                     : null;
        w.agentPrimaryColor   = msg.Agent__r != null ? msg.Agent__r.Primary_Color__c          : null;
        w.agentAvatarUrl      = (msg.Agent__r != null && String.isNotBlank(msg.Agent__r.Avatar_Static_Resource__c))
                                    ? '/resource/' + msg.Agent__r.Avatar_Static_Resource__c
                                    : null;
        // Raw Datetime, not String.valueOf() — the Aura/LWC serializer emits proper
        // ISO-8601 for @AuraEnabled Datetime fields. String.valueOf() previously
        // produced "yyyy-MM-dd HH:mm:ss" (no T/zone), which `new Date(ts)` in the LWC
        // parses as Invalid Date on Safari/iOS (non-ISO strings are implementation-defined).
        w.startedAt         = msg.Started_At__c;
        w.endedAt           = msg.Ended_At__c;
        w.durationMs        = msg.Duration_ms__c?.longValue();
        w.cost              = msg.Cost__c;
        w.modelName         = msg.Model_Name__c;
        w.inputTokens       = msg.Input_Tokens__c?.longValue();
        w.outputTokens      = msg.Output_Tokens__c?.longValue();
        w.cachedInputTokens = msg.Cached_Input_Tokens__c?.longValue();
        w.reasoningTokens   = msg.Reasoning_Tokens__c?.longValue();
        w.userName          = msg.CreatedBy?.Name;
        w.feedback          = msg.Feedback__c;
        w.feedbackNotes     = msg.Feedback_Notes__c;

        List<ToolLogWrapper> tlWrappers = new List<ToolLogWrapper>();
        if (msg.Tool_Logs__r != null) {
            for (ApexAgent_Tool_Log__c tl : msg.Tool_Logs__r) {
                ToolLogWrapper tlw  = new ToolLogWrapper();
                tlw.executionMessage = tl.Execution_Message__c;
                tlw.status           = tl.Status__c;
                tlWrappers.add(tlw);
            }
        }
        w.toolCallCount = tlWrappers.size();
        w.toolLogs      = tlWrappers;

        List<ErrorLogWrapper> elWrappers = new List<ErrorLogWrapper>();
        if (msg.Error_Logs__r != null) {
            for (ApexAgent_Error_Log__c el : msg.Error_Logs__r) {
                ErrorLogWrapper elw = new ErrorLogWrapper();
                elw.error      = el.Error__c;
                elw.stackTrace = el.Stack_Trace__c;
                elWrappers.add(elw);
            }
        }
        w.errorLogs = elWrappers;
        return w;
    }
}
