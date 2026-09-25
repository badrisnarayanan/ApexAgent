trigger ApexAgentMcpToolMapTrigger on ApexAgent_MCP_Tool_Map__c (before insert, before update) {
    ApexAgentJunctionKeyService.populateUniqueKeys(Trigger.new, ApexAgent_MCP_Tool_Map__c.MCP__c, ApexAgent_MCP_Tool_Map__c.Tool__c);
}
