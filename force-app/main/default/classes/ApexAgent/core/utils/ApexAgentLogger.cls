/**
 * Inserts all observability records (Thread, Message, Tool, Error logs)
 * at the end of an agent execution run.
 */
public with sharing class ApexAgentLogger {

    private static final Integer MAX_FIELD_LENGTH = 131072;

    // ─────────────────────────────────────────────────────────────────
    // Payload — flat struct carrying all data from the orchestrator
    // ─────────────────────────────────────────────────────────────────

    public class LogPayload {
        public Id agentId;
        public String threadUUID;
        public String messageUUID;
        public String agentName;
        public String modelName;
        public String userInput;
        public String agentResponse;
        public String thoughtContent;
        public String thoughtSignature;
        public Datetime startedAt;
        public Datetime endedAt;
        public Integer promptTokens;
        public Integer completionTokens;
        public Integer cachedTokens;
        public Integer reasoningTokens;
        public Integer totalTokens;
        public Decimal cost;
        public List<ToolLogEntry> toolLogs;
        public String errorMessage;
        public String errorStackTrace;
    }

    public class ToolLogEntry {
        public String toolCallId;
        public String toolName;
        public String inputJson;
        public String outputJson;
        public String status;          // Success / Error
        public String errorMessage;
        public String stackTrace;
        public String thoughtSignature;
        public Datetime startedAt;
        public Datetime endedAt;
    }

    // ─────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────

    public static void insertLogs(LogPayload p) {
        Id threadId = upsertThread(p.threadUUID, p.startedAt);
        Id messageLogId = insertMessageLog(p, threadId);
        insertToolLogs(p.toolLogs, messageLogId);
        if (String.isNotBlank(p.errorMessage)) {
            insertErrorLog(p.errorMessage, p.errorStackTrace, messageLogId);
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: thread upsert
    // ─────────────────────────────────────────────────────────────────

    private static Id upsertThread(String threadUUID, Datetime startedAt) {
        if (String.isBlank(threadUUID)) {
            return null; // stateless / one-shot call — no thread record needed
        }

        List<ApexAgent_Thread_Log__c> existing = [
            SELECT Id FROM ApexAgent_Thread_Log__c
            WHERE Agent_Thread_UUID__c = :threadUUID
            WITH USER_MODE
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            ApexAgent_Thread_Log__c upd = new ApexAgent_Thread_Log__c(
                Id = existing[0].Id,
                Last_Activity_At__c = Datetime.now()
            );
            update upd; // NOPMD — log objects require system-level DML; users lack write access
            return existing[0].Id;
        }

        ApexAgent_Thread_Log__c thread = new ApexAgent_Thread_Log__c(
            Agent_Thread_UUID__c = threadUUID,
            Started_At__c        = startedAt,
            Last_Activity_At__c  = Datetime.now()
        );
        insert thread; // NOPMD
        return thread.Id;
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: message log insert
    // ─────────────────────────────────────────────────────────────────

    private static Id insertMessageLog(LogPayload p, Id threadId) {
        Long durationMs = p.startedAt != null && p.endedAt != null
            ? p.endedAt.getTime() - p.startedAt.getTime()
            : null;

        ApexAgent_Message_Log__c msg = new ApexAgent_Message_Log__c(
            Thread__c                   = threadId,
            Agent__c                    = p.agentId,
            Agent_Message_UUID__c       = p.messageUUID,
            User_Input__c               = truncate(p.userInput),
            Agent_Response__c           = truncate(p.agentResponse),
            Agent_Thought_Signature__c  = truncate(p.thoughtSignature),
            Model_Name__c               = p.modelName,
            Started_At__c               = p.startedAt,
            Ended_At__c                 = p.endedAt,
            Duration_ms__c              = durationMs,
            Input_Tokens__c             = p.promptTokens,
            Cached_Input_Tokens__c      = p.cachedTokens,
            Output_Tokens__c            = p.completionTokens,
            Reasoning_Tokens__c         = p.reasoningTokens,
            Cost__c                     = p.cost
        );
        insert msg; // NOPMD
        return msg.Id;
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: tool log inserts
    // ─────────────────────────────────────────────────────────────────

    private static void insertToolLogs(List<ToolLogEntry> entries, Id messageLogId) {
        if (entries == null || entries.isEmpty()) {
            return;
        }

        List<ApexAgent_Tool_Log__c> records = new List<ApexAgent_Tool_Log__c>();
        for (ToolLogEntry entry : entries) {
            Long durMs = entry.startedAt != null && entry.endedAt != null
                ? entry.endedAt.getTime() - entry.startedAt.getTime()
                : null;

            records.add(new ApexAgent_Tool_Log__c(
                Message_Log__c              = messageLogId,
                Tool_Name__c               = entry.toolName,
                Tool_Call_Id__c            = entry.toolCallId,
                Agent_Thought_Signature__c = truncate(entry.thoughtSignature),
                Started_At__c              = entry.startedAt,
                Ended_At__c                = entry.endedAt,
                Duration_ms__c             = durMs,
                Input__c                   = truncate(entry.inputJson),
                Output__c                  = truncate(entry.outputJson),
                Status__c                  = entry.status,
                Error_Message__c           = truncate(entry.errorMessage),
                Stack_Trace__c             = truncate(entry.stackTrace)
            ));
        }
        insert records; // NOPMD
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: error log insert
    // ─────────────────────────────────────────────────────────────────

    private static void insertErrorLog(String errorMsg, String stackTrace, Id messageLogId) {
        insert new ApexAgent_Error_Log__c( // NOPMD
            Message_Log__c = messageLogId,
            Error__c       = truncate(errorMsg),
            Stack_Trace__c = truncate(stackTrace)
        );
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: truncation helper
    // ─────────────────────────────────────────────────────────────────

    private static String truncate(String value) {
        if (value == null) {
            return null;
        }
        return value.length() > MAX_FIELD_LENGTH
            ? value.substring(0, MAX_FIELD_LENGTH)
            : value;
    }
}
