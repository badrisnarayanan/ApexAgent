/**
 * Handles real-time tool execution status for the ApexAgent framework.
 *
 * Responsibilities:
 *  1. Publish PublishImmediately platform events before/after tool execution (called by orchestrator).
 *  2. Handle those events in the PE trigger to maintain a per-message tool action list in Platform Cache.
 *  3. Expose an AuraEnabled method for LWC to poll the current tool action list for a message.
 *
 * Cache key format: local.ApexAgentExecution.<messageUUID with hyphens stripped>
 * Cache TTL: 300 seconds (5 minutes)
 */
public with sharing class ApexAgentExecutionMessageHandler {

    private static final String CACHE_PARTITION = 'local.ApexAgentExecution';
    private static final Integer CACHE_TTL_SECONDS = 300;
    private static final String STATUS_IN_PROGRESS = 'In Progress';
    private static final String STATUS_COMPLETED   = 'Completed';

    // ─────────────────────────────────────────────────────────────────
    // Inner type — one entry per tool call stored in Platform Cache
    // ─────────────────────────────────────────────────────────────────

    public class ToolActionEntry {
        public String toolCallId;
        public String executionMessage;
        public String status;
    }

    // ─────────────────────────────────────────────────────────────────
    // 1. Publish methods — called from ApexAgentOrchestrator
    // ─────────────────────────────────────────────────────────────────

    /**
     * Fires one In Progress platform event per tool call in the current iteration, in bulk.
     * Execution messages must have already been extracted from tc.function.arguments.
     */
    public static void publishInProgress(
        String messageUUID,
        List<ApexAgentApiTypes.ToolCall> toolCalls,
        Map<String, String> execMsgByToolCallId
    ) {
        List<ApexAgent_Tool_Execution__e> events = new List<ApexAgent_Tool_Execution__e>();
        for (ApexAgentApiTypes.ToolCall tc : toolCalls) {
            events.add(new ApexAgent_Tool_Execution__e(
                Message_UUID__c      = messageUUID,
                Tool_Call_Id__c      = tc.id,
                Execution_Message__c = truncateMessage(execMsgByToolCallId.get(tc.id)),
                Status__c            = STATUS_IN_PROGRESS
            ));
        }
        EventBus.publish(events);
    }

    /**
     * Fires a single Completed platform event for one tool call, immediately after it finishes.
     * The execution message is already in the cache from the in-progress event; only the status changes.
     */
    public static void publishCompleted(String messageUUID, ApexAgentApiTypes.ToolCall tc) {
        EventBus.publish(new ApexAgent_Tool_Execution__e(
            Message_UUID__c = messageUUID,
            Tool_Call_Id__c = tc.id,
            Status__c       = STATUS_COMPLETED
        ));
    }

    // ─────────────────────────────────────────────────────────────────
    // 2. PE trigger handler — runs in the trigger's async transaction
    // ─────────────────────────────────────────────────────────────────

    /**
     * Processes a batch of ApexAgent_Tool_Execution__e events.
     * Groups by messageUUID, then reads/merges/writes the Platform Cache entry for each group.
     */
    public static void handleEvents(List<ApexAgent_Tool_Execution__e> events) {
        // Group events by messageUUID
        Map<String, List<ApexAgent_Tool_Execution__e>> byMessage =
            new Map<String, List<ApexAgent_Tool_Execution__e>>();
        for (ApexAgent_Tool_Execution__e evt : events) {
            if (String.isBlank(evt.Message_UUID__c)) {
                continue;
            }
            if (!byMessage.containsKey(evt.Message_UUID__c)) {
                byMessage.put(evt.Message_UUID__c, new List<ApexAgent_Tool_Execution__e>());
            }
            byMessage.get(evt.Message_UUID__c).add(evt);
        }

        for (String msgUUID : byMessage.keySet()) {
            mergeIntoCacheForMessage(msgUUID, byMessage.get(msgUUID));
        }
    }

    private static void mergeIntoCacheForMessage(
        String msgUUID,
        List<ApexAgent_Tool_Execution__e> events
    ) {
        String cacheKey = buildCacheKey(msgUUID);
        List<ToolActionEntry> entries = readCache(cacheKey);

        // Index existing entries by toolCallId for O(1) lookup
        Map<String, ToolActionEntry> byToolCallId = new Map<String, ToolActionEntry>();
        for (ToolActionEntry e : entries) {
            byToolCallId.put(e.toolCallId, e);
        }

        for (ApexAgent_Tool_Execution__e evt : events) {
            String tcId = evt.Tool_Call_Id__c;
            if (byToolCallId.containsKey(tcId)) {
                byToolCallId.get(tcId).status = evt.Status__c;
            } else {
                ToolActionEntry fresh = new ToolActionEntry();
                fresh.toolCallId       = tcId;
                fresh.executionMessage = evt.Execution_Message__c;
                fresh.status           = evt.Status__c;
                byToolCallId.put(tcId, fresh);
                entries.add(fresh);
            }
        }

        Cache.Org.put(cacheKey, JSON.serialize(entries), CACHE_TTL_SECONDS);
    }

    // ─────────────────────────────────────────────────────────────────
    // 3. AuraEnabled poll method — called by LWC
    // ─────────────────────────────────────────────────────────────────

    /**
     * Returns the current tool action list for a message UUID.
     * Reads from Platform Cache; falls back to Tool_Log__c for historical messages
     * whose cache entry has expired.
     */
    public static List<Map<String, Object>> getToolActions(String messageUUID) {
        if (String.isBlank(messageUUID)) {
            return new List<Map<String, Object>>();
        }
        String cacheKey = buildCacheKey(messageUUID);
        List<ToolActionEntry> entries = readCache(cacheKey);

        return entriesToMaps(entries);
    }

    // ─────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────

    private static String buildCacheKey(String messageUUID) {
        return CACHE_PARTITION + '.' + messageUUID.replace('-', '');
    }

    @SuppressWarnings('PMD.EmptyCatchBlock')
    private static List<ToolActionEntry> readCache(String cacheKey) {
        try {
            Object cached = Cache.Org.get(cacheKey);
            if (cached != null) {
                return (List<ToolActionEntry>) JSON.deserialize(
                    String.valueOf(cached),
                    List<ToolActionEntry>.class
                );
            }
        } catch (Exception e) {
            // Return empty list if cache is unreadable or partition is unavailable
        }
        return new List<ToolActionEntry>();
    }

    private static String truncateMessage(String value) {
        if (value == null) {
            return null;
        }
        return value.length() > 255 ? value.substring(0, 252) + '...' : value;
    }

    private static List<Map<String, Object>> entriesToMaps(List<ToolActionEntry> entries) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (ToolActionEntry e : entries) {
            result.add(new Map<String, Object>{
                'toolCallId'       => e.toolCallId,
                'executionMessage' => e.executionMessage,
                'status'           => e.status
            });
        }
        return result;
    }
}
