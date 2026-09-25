public with sharing class ApexAgentThreadViewerController {

    // Most recent messages shown per thread — without this, a long-running thread
    // re-queries and re-transmits its entire history every 5s poll indefinitely.
    private static final Integer MAX_MESSAGES = 100;

    @AuraEnabled(cacheable=false)
    public static List<ApexAgentConversationLogService.MessageWrapper> getThreadMessages(Id threadId) {
        return ApexAgentConversationLogService.getThreadMessages(threadId, MAX_MESSAGES);
    }
}
