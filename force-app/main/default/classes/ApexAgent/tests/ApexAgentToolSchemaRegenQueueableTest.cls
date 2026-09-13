/**
 * Verifies ApexAgentToolSchemaRegenQueueable regenerates Schema__c for
 * a valid tool class, while a tool whose class can't be resolved is left
 * completely untouched — its previous Schema__c (if any) survives rather than
 * being overwritten with a broken value. Both outcomes are exercised in one
 * batch to also confirm one bad class doesn't block the good one.
 */
@IsTest
private class ApexAgentToolSchemaRegenQueueableTest {

    @IsTest
    static void testRegeneratesValidToolAndLeavesInvalidOneUntouched() {
        ApexAgent_Tool__c validTool = new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetFieldDetails');
        ApexAgent_Tool__c invalidTool = new ApexAgent_Tool__c(
            Apex_Class_Name__c = 'ThisApexClassDoesNotExist123',
            Schema__c = 'previously-generated-good-schema'
        );
        insert new List<ApexAgent_Tool__c>{ validTool, invalidTool };

        Test.startTest();
        // An empty/no-op id set must also be handled without error.
        System.enqueueJob(new ApexAgentToolSchemaRegenQueueable(new Set<Id>()));
        System.enqueueJob(new ApexAgentToolSchemaRegenQueueable(
            new Set<Id>{ validTool.Id, invalidTool.Id }
        ));
        Test.stopTest();

        Map<Id, ApexAgent_Tool__c> toolsById = new Map<Id, ApexAgent_Tool__c>([
            SELECT Schema__c FROM ApexAgent_Tool__c WHERE Id IN :new Set<Id>{ validTool.Id, invalidTool.Id }
        ]);

        String schemaJson = toolsById.get(validTool.Id).Schema__c;
        Assert.isNotNull(schemaJson, 'A valid tool class must have its schema generated');
        Map<String, Object> def = (Map<String, Object>) JSON.deserializeUntyped(schemaJson);
        Map<String, Object> function = (Map<String, Object>) def.get('function');
        Assert.areEqual('GetFieldDetails', function.get('name'), 'The generated schema must describe the right tool');

        Assert.areEqual('previously-generated-good-schema', toolsById.get(invalidTool.Id).Schema__c,
            'A tool whose class can\'t be resolved must keep its prior Schema__c untouched, never overwritten with a broken value');
    }
}
