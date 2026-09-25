public with sharing class ApexAgentMessageViewerController {

    @AuraEnabled(cacheable=false)
    public static ApexAgentConversationLogService.MessageWrapper getMessage(Id messageId) {
        return ApexAgentConversationLogService.getMessage(messageId);
    }
}
