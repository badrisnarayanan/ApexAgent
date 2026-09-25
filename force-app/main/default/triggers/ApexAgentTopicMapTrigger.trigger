trigger ApexAgentTopicMapTrigger on ApexAgent_Topic_Map__c (before insert, before update) {
    ApexAgentJunctionKeyService.populateUniqueKeys(Trigger.new, ApexAgent_Topic_Map__c.Agent__c, ApexAgent_Topic_Map__c.Topic__c);
}
