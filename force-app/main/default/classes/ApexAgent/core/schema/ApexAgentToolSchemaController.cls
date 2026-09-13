/**
 * AuraEnabled controller for the "Regenerate Schema" quick action on the
 * Agent Tool record page. Actual schema generation always runs in
 * ApexAgentToolSchemaRegenQueueable — this only enqueues it, since
 * ApexAgentSymbolTableService needs a callout and no callout can be made
 * directly from this synchronous Aura/LWC request.
 */
public with sharing class ApexAgentToolSchemaController {

    @AuraEnabled
    public static void regenerateSchema(Id toolId) {
        if (toolId == null) {
            throw new AuraHandledException('A tool record Id is required to regenerate its schema.');
        }
        if (!Schema.sObjectType.ApexAgent_Tool__c.fields.Schema__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to regenerate this tool\'s schema.');
        }
        System.enqueueJob(new ApexAgentToolSchemaRegenQueueable(new Set<Id>{ toolId }));
    }
}
