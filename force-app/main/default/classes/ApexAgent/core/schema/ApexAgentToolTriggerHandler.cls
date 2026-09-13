/**
 * Decides which ApexAgent_Tool__c records need their Schema__c regenerated after
 * a save, and enqueues ApexAgentToolSchemaRegenQueueable for them.
 *
 * Regeneration is triggered by insert, or by an update that changes
 * Apex_Class_Name__c — never by any other field change. This doubles as the
 * recursion guard: the queueable's own update only ever sets Schema__c, so the
 * after-update trigger it causes finds Apex_Class_Name__c unchanged and enqueues
 * nothing, ending the loop.
 */
public with sharing class ApexAgentToolTriggerHandler {

    public static void handleAfterSave(List<ApexAgent_Tool__c> newTools, Map<Id, ApexAgent_Tool__c> oldToolsById) {
        Set<Id> toolIdsToRegenerate = new Set<Id>();

        for (ApexAgent_Tool__c tool : newTools) {
            if (String.isBlank(tool.Apex_Class_Name__c)) {
                continue;
            }
            ApexAgent_Tool__c oldTool = oldToolsById == null ? null : oldToolsById.get(tool.Id);
            Boolean isNewRecord = oldTool == null;
            Boolean classNameChanged = !isNewRecord && tool.Apex_Class_Name__c != oldTool.Apex_Class_Name__c;
            if (isNewRecord || classNameChanged) {
                toolIdsToRegenerate.add(tool.Id);
            }
        }

        if (!toolIdsToRegenerate.isEmpty()) {
            System.enqueueJob(new ApexAgentToolSchemaRegenQueueable(toolIdsToRegenerate));
        }
    }
}
