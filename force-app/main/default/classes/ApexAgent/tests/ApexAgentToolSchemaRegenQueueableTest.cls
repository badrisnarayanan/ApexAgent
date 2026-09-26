/**
 * Verifies ApexAgentToolSchemaRegenQueueable regenerates both Schema__c (chat)
 * and MCP_Schema__c (MCP, with readOnlyHint derived from
 * Modifies_Salesforce_Data__c) for valid tool classes, while a tool whose class
 * can't be resolved is left completely untouched — its previous values in both
 * fields survive rather than being overwritten with a broken value. All
 * outcomes are exercised in one batch to also confirm one bad class doesn't
 * block the good ones.
 */
@IsTest
private class ApexAgentToolSchemaRegenQueueableTest {

    @IsTest
    static void testRegeneratesValidToolsAndLeavesInvalidOneUntouched() {
        // ApexAgentGetFieldDetails outputs a nested Apex class, so its symbol table is queried.
        ApexAgentSymbolTableTypes.ToolingQueryResult noSymbolTables = new ApexAgentSymbolTableTypes.ToolingQueryResult();
        noSymbolTables.records = new List<ApexAgentSymbolTableTypes.ApexClassRecord>();
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, JSON.serialize(noSymbolTables)));

        ApexAgent_Tool__c readOnlyTool = new ApexAgent_Tool__c(Apex_Class_Name__c = 'ApexAgentGetFieldDetails');
        ApexAgent_Tool__c writeTool = new ApexAgent_Tool__c(
            Apex_Class_Name__c = 'ApexAgentGetObjectApiName',
            Modifies_Salesforce_Data__c = true
        );
        ApexAgent_Tool__c invalidTool = new ApexAgent_Tool__c(
            Apex_Class_Name__c = 'ThisApexClassDoesNotExist123',
            Schema__c = 'previously-generated-good-schema',
            MCP_Schema__c = 'previously-generated-good-mcp-schema'
        );
        insert new List<ApexAgent_Tool__c>{ readOnlyTool, writeTool, invalidTool };

        Test.startTest();
        // An empty/no-op id set must also be handled without error.
        System.enqueueJob(new ApexAgentToolSchemaRegenQueueable(new Set<Id>()));
        System.enqueueJob(new ApexAgentToolSchemaRegenQueueable(
            new Set<Id>{ readOnlyTool.Id, writeTool.Id, invalidTool.Id }
        ));
        Test.stopTest();

        Map<Id, ApexAgent_Tool__c> toolsById = new Map<Id, ApexAgent_Tool__c>([
            SELECT Schema__c, MCP_Schema__c FROM ApexAgent_Tool__c
            WHERE Id IN :new Set<Id>{ readOnlyTool.Id, writeTool.Id, invalidTool.Id }
        ]);

        Map<String, Object> chatDef = (Map<String, Object>) JSON.deserializeUntyped(toolsById.get(readOnlyTool.Id).Schema__c);
        Map<String, Object> function = (Map<String, Object>) chatDef.get('function');
        Assert.areEqual('ApexAgentGetFieldDetails', function.get('name'), 'The generated chat schema must describe the right tool');

        Map<String, Object> readOnlyMcp = (Map<String, Object>) JSON.deserializeUntyped(toolsById.get(readOnlyTool.Id).MCP_Schema__c);
        Assert.areEqual('ApexAgentGetFieldDetails', readOnlyMcp.get('name'), 'The generated MCP schema must describe the right tool');
        Assert.isNotNull(readOnlyMcp.get('inputSchema'), 'The MCP schema must carry an inputSchema');
        Assert.isNotNull(readOnlyMcp.get('outputSchema'), 'The MCP schema must carry an outputSchema');
        Map<String, Object> readOnlyAnnotations = (Map<String, Object>) readOnlyMcp.get('annotations');
        Assert.areEqual(true, readOnlyAnnotations.get('readOnlyHint'), 'A tool that does not modify data is read-only');
        Assert.areEqual(false, readOnlyAnnotations.get('openWorldHint'), 'Every tool works only on this org\'s data');
        Assert.areEqual(readOnlyMcp.get('title'), readOnlyAnnotations.get('title'), 'The title should be repeated in the annotations');

        Map<String, Object> writeMcp = (Map<String, Object>) JSON.deserializeUntyped(toolsById.get(writeTool.Id).MCP_Schema__c);
        Assert.areEqual(false, ((Map<String, Object>) writeMcp.get('annotations')).get('readOnlyHint'),
            'A tool with Modifies_Salesforce_Data__c set must not be flagged read-only');

        Assert.areEqual('previously-generated-good-schema', toolsById.get(invalidTool.Id).Schema__c,
            'A tool whose class can\'t be resolved must keep its prior Schema__c untouched, never overwritten with a broken value');
        Assert.areEqual('previously-generated-good-mcp-schema', toolsById.get(invalidTool.Id).MCP_Schema__c,
            'A tool whose class can\'t be resolved must keep its prior MCP_Schema__c untouched too');
    }
}
