public with sharing class ApexAgentThreadViewerController {

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
        @AuraEnabled public String             startedAt;
        @AuraEnabled public String             endedAt;
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
            ORDER BY Started_At__c ASC NULLS LAST
        ];

        List<MessageWrapper> result = new List<MessageWrapper>();
        for (ApexAgent_Message_Log__c msg : messages) {
            result.add(toWrapper(msg));
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
        w.startedAt       = msg.Started_At__c  != null ? String.valueOf(msg.Started_At__c)  : null;
        w.endedAt         = msg.Ended_At__c    != null ? String.valueOf(msg.Ended_At__c)    : null;
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
