public with sharing class ApexAgentThreadViewerController {

    // Most recent messages shown per thread — without this, a long-running thread
    // re-queries and re-transmits its entire history every 5s poll indefinitely.
    private static final Integer MAX_MESSAGES = 100;

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
        @AuraEnabled public Integer            toolCallCount;
        @AuraEnabled public List<ToolLogWrapper>   toolLogs;
        @AuraEnabled public List<ErrorLogWrapper>  errorLogs;
        @AuraEnabled public String             userName;
        @AuraEnabled public String             agentPrimaryColor;
        @AuraEnabled public String             agentAvatarUrl;
        @AuraEnabled public String             feedback;
        @AuraEnabled public String             feedbackNotes;
    }

    @AuraEnabled(cacheable=false)
    public static List<MessageWrapper> getThreadMessages(Id threadId) {
        if (threadId == null) {
            return new List<MessageWrapper>();
        }
        List<ApexAgent_Message_Log__c> messages = [
            SELECT Id,
                   User_Input__c,
                   Agent_Response__c,
                   Agent__r.Name,
                   Agent__r.Primary_Color__c,
                   Agent__r.Avatar_Static_Resource__c,
                   Started_At__c,
                   Ended_At__c,
                   Duration_ms__c,
                   Cost__c,
                   CreatedBy.Name,
                   Feedback__c,
                   Feedback_Notes__c,
                   (SELECT Id, Execution_Message__c, Status__c
                    FROM Tool_Logs__r
                    ORDER BY CreatedDate ASC),
                   (SELECT Error__c, Stack_Trace__c
                    FROM Error_Logs__r
                    ORDER BY CreatedDate ASC)
            FROM ApexAgent_Message_Log__c
            WHERE Thread__c = :threadId
            WITH USER_MODE
            ORDER BY Started_At__c DESC NULLS LAST
            LIMIT :MAX_MESSAGES
        ];

        // Query above orders DESC to pick the most recent MAX_MESSAGES rows; reverse
        // here so the LWC still receives chronological (oldest-first) order.
        List<MessageWrapper> result = new List<MessageWrapper>();
        for (Integer i = messages.size() - 1; i >= 0; i--) {
            result.add(toWrapper(messages[i]));
        }
        return result;
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
        w.startedAt       = msg.Started_At__c;
        w.endedAt         = msg.Ended_At__c;
        w.durationMs      = msg.Duration_ms__c != null ? msg.Duration_ms__c.longValue()     : null;
        w.cost            = msg.Cost__c;
        w.userName        = msg.CreatedBy?.Name;
        w.feedback        = msg.Feedback__c;
        w.feedbackNotes   = msg.Feedback_Notes__c;

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
