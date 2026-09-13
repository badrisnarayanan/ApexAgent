trigger ApexAgentToolTrigger on ApexAgent_Tool__c (after insert, after update) {
    ApexAgentToolTriggerHandler.handleAfterSave(Trigger.new, Trigger.oldMap);
}
