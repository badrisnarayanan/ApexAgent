trigger ApexAgentTopicToolMapTrigger on ApexAgent_Topic_Tool_Map__c (before insert, before update) {
    ApexAgentJunctionKeyService.populateUniqueKeys(Trigger.new, ApexAgent_Topic_Tool_Map__c.Topic__c, ApexAgent_Topic_Tool_Map__c.Tool__c);
}
