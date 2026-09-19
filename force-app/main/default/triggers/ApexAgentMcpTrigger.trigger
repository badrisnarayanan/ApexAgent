trigger ApexAgentMcpTrigger on ApexAgent_MCP__c (before insert, before update) {
    ApexAgentMcpTriggerHandler.populateEndpointUrl(Trigger.new, Trigger.oldMap);
}
