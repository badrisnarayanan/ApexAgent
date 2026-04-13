/**
 * AuraEnabled controller for the ApexAgent Chat LWC components.
 * Provides agent config, thread history, message history, send-message,
 * feedback persistence, and real-time execution message polling.
 */
public with sharing class ApexAgentChatController {

    private static final String  DEFAULT_PRIMARY_COLOR = '#0176D3';
    private static final Integer FIRST_MSG_MAX_LEN     = 60;

    // ─────────────────────────────────────────────────────────────────────────
    // Inner types
    // ─────────────────────────────────────────────────────────────────────────

    public class AgentConfig {
        @AuraEnabled public String  name;
        @AuraEnabled public String  tagline;
        @AuraEnabled public String  primaryColor;
        @AuraEnabled public Boolean showExecutionMessage;
        @AuraEnabled public String  avatarUrl;
    }

    public class ThreadSummary {
        @AuraEnabled public String   threadUUID;
        @AuraEnabled public String   firstMessage;
        @AuraEnabled public DateTime lastActivity;
        @AuraEnabled public Id       threadLogId;
    }

    public class MessageData {
        @AuraEnabled public Id               messageLogId;
        @AuraEnabled public String           agentMessageUUID;
        @AuraEnabled public String           userInput;
        @AuraEnabled public String           agentResponse;
        @AuraEnabled public DateTime         startedAt;
        @AuraEnabled public DateTime         endedAt;
        @AuraEnabled public String           feedback;
        @AuraEnabled public String           feedbackNotes;
        @AuraEnabled public List<ToolLogData>  toolLogs;
        @AuraEnabled public List<ErrorLogData> errorLogs;
    }

    public class ToolLogData {
        @AuraEnabled public String executionMessage;
        @AuraEnabled public String status;
    }

    public class ErrorLogData {
        @AuraEnabled public String error;
        @AuraEnabled public String stackTrace;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public AuraEnabled methods
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns branding and behaviour config for the given agent.
     * Returns null if the agent does not exist.
     */
    @AuraEnabled(cacheable=true)
    public static AgentConfig getAgentConfig(String agentName) {
        if (String.isBlank(agentName)) {
            return null;
        }
        List<ApexAgent_Agent__c> agents = [
            SELECT Name, Tagline__c, Primary_Color__c,
                   Show_Execution_Message__c, Avatar_Static_Resource__c
            FROM ApexAgent_Agent__c
            WHERE Name = :agentName
            WITH USER_MODE
            LIMIT 1
        ];
        if (agents.isEmpty()) {
            return null;
        }
        ApexAgent_Agent__c agent = agents[0];
        AgentConfig config       = new AgentConfig();
        config.name                 = agent.Name;
        config.tagline              = agent.Tagline__c;
        config.primaryColor         = String.isNotBlank(agent.Primary_Color__c)
                                        ? agent.Primary_Color__c
                                        : DEFAULT_PRIMARY_COLOR;
        config.showExecutionMessage = agent.Show_Execution_Message__c;
        config.avatarUrl            = String.isNotBlank(agent.Avatar_Static_Resource__c)
                                        ? '/resource/' + agent.Avatar_Static_Resource__c
                                        : null;
        return config;
    }

    /**
     * Returns the 50 most recent threads for the running user that contain
     * at least one message processed by the given agent.
     */
    @AuraEnabled(cacheable=false)
    public static List<ThreadSummary> getThreads(String agentName) {
        if (String.isBlank(agentName)) {
            return new List<ThreadSummary>();
        }
        List<ApexAgent_Thread_Log__c> threads = [
            SELECT Id, Agent_Thread_UUID__c, Last_Activity_At__c,
                   (SELECT User_Input__c FROM Message_Logs__r ORDER BY CreatedDate ASC LIMIT 1)
            FROM ApexAgent_Thread_Log__c
            WHERE OwnerId = :UserInfo.getUserId()
              AND Id IN (
                SELECT Thread__c
                FROM ApexAgent_Message_Log__c
                WHERE Agent__r.Name = :agentName
              )
            WITH USER_MODE
            ORDER BY Last_Activity_At__c DESC
            LIMIT 50
        ];
        List<ThreadSummary> results = new List<ThreadSummary>();
        for (ApexAgent_Thread_Log__c t : threads) {
            ThreadSummary ts  = new ThreadSummary();
            ts.threadUUID     = t.Agent_Thread_UUID__c;
            ts.lastActivity   = t.Last_Activity_At__c;
            ts.threadLogId    = t.Id;
            ts.firstMessage   = extractFirstMessage(t.Message_Logs__r);
            results.add(ts);
        }
        return results;
    }

    /**
     * Returns all messages for a thread, including nested tool logs and error logs,
     * ordered by start time ascending.
     */
    @AuraEnabled(cacheable=false)
    public static List<MessageData> getMessages(String threadUUID) {
        if (String.isBlank(threadUUID)) {
            return new List<MessageData>();
        }
        List<ApexAgent_Message_Log__c> messages = [
            SELECT Id, Agent_Message_UUID__c, User_Input__c, Agent_Response__c,
                   Started_At__c, Ended_At__c, Feedback__c, Feedback_Notes__c,
                   (SELECT Execution_Message__c, Status__c
                    FROM Tool_Logs__r ORDER BY Started_At__c ASC),
                   (SELECT Error__c, Stack_Trace__c
                    FROM Error_Logs__r ORDER BY CreatedDate ASC)
            FROM ApexAgent_Message_Log__c
            WHERE Thread__r.Agent_Thread_UUID__c = :threadUUID
            WITH USER_MODE
            ORDER BY Started_At__c ASC
        ];
        List<MessageData> results = new List<MessageData>();
        for (ApexAgent_Message_Log__c msg : messages) {
            results.add(toMessageData(msg));
        }
        return results;
    }

    /**
     * Sends a user message through the orchestrator and returns the LLM response.
     */
    @AuraEnabled
    public static ApexAgentOrchestrator.AgentResponse sendMessage(
        String agentName,
        String userMessage,
        String threadUUID,
        String messageUUID,
        String context
    ) {
        return ApexAgentOrchestrator.run(threadUUID, userMessage, context, agentName, messageUUID);
    }

    /**
     * Persists thumbs-up / thumbs-down feedback on a message log record,
     * identified by its external ID (Agent_Message_UUID__c).
     */
    @AuraEnabled
    public static void saveFeedback(String messageUUID, String feedback, String feedbackNotes) {
        ApexAgent_Message_Log__c log = new ApexAgent_Message_Log__c(
            Agent_Message_UUID__c = messageUUID,
            Feedback__c           = feedback,
            Feedback_Notes__c     = feedbackNotes
        );
        upsert as user log ApexAgent_Message_Log__c.Agent_Message_UUID__c;
    }

    /**
     * Returns real-time tool execution actions for an in-flight message from Platform Cache.
     * LWC polls this at 1500ms intervals while a message is being processed.
     */
    @AuraEnabled(cacheable=false)
    public static List<Object> getExecutionMessages(String messageUUID) {
        return ApexAgentExecutionMessageHandler.getToolActions(messageUUID);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static String extractFirstMessage(List<ApexAgent_Message_Log__c> msgLogs) {
        if (msgLogs == null || msgLogs.isEmpty() || String.isBlank(msgLogs[0].User_Input__c)) {
            return '';
        }
        String raw = msgLogs[0].User_Input__c;
        return raw.length() > FIRST_MSG_MAX_LEN ? raw.substring(0, FIRST_MSG_MAX_LEN) : raw;
    }

    private static MessageData toMessageData(ApexAgent_Message_Log__c msg) {
        MessageData md       = new MessageData();
        md.messageLogId      = msg.Id;
        md.agentMessageUUID  = msg.Agent_Message_UUID__c;
        md.userInput         = msg.User_Input__c;
        md.agentResponse     = msg.Agent_Response__c;
        md.startedAt         = msg.Started_At__c;
        md.endedAt           = msg.Ended_At__c;
        md.feedback          = msg.Feedback__c;
        md.feedbackNotes     = msg.Feedback_Notes__c;
        md.toolLogs          = toToolLogData(msg.Tool_Logs__r);
        md.errorLogs         = toErrorLogData(msg.Error_Logs__r);
        return md;
    }

    private static List<ToolLogData> toToolLogData(List<ApexAgent_Tool_Log__c> toolLogs) {
        List<ToolLogData> result = new List<ToolLogData>();
        if (toolLogs == null) {
            return result;
        }
        for (ApexAgent_Tool_Log__c tl : toolLogs) {
            ToolLogData td      = new ToolLogData();
            td.executionMessage = tl.Execution_Message__c;
            td.status           = tl.Status__c;
            result.add(td);
        }
        return result;
    }

    private static List<ErrorLogData> toErrorLogData(List<ApexAgent_Error_Log__c> errorLogs) {
        List<ErrorLogData> result = new List<ErrorLogData>();
        if (errorLogs == null) {
            return result;
        }
        for (ApexAgent_Error_Log__c el : errorLogs) {
            ErrorLogData ed = new ErrorLogData();
            ed.error        = el.Error__c;
            ed.stackTrace   = el.Stack_Trace__c;
            result.add(ed);
        }
        return result;
    }
}
