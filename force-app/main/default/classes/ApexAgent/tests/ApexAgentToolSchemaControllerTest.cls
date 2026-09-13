/**
 * Verifies the "Regenerate Schema" quick action's controller: it rejects a
 * missing record Id up front, and otherwise enqueues regeneration itself —
 * asserted via the Limits governor counter (isolating the controller's own
 * enqueue call from the insert trigger's, which never gets a chance to flush
 * here since the insert happens before Test.startTest()) — and that the
 * enqueued job actually runs by the time the test stops.
 */
@IsTest
private class ApexAgentToolSchemaControllerTest {

    @IsTest
    static void testRegenerateSchemaThrowsWithoutARecordId() {
        try {
            ApexAgentToolSchemaController.regenerateSchema(null);
            Assert.fail('Expected an AuraHandledException for a null tool Id');
        } catch (AuraHandledException e) {
            // Message text isn't asserted, per AuraHandledException's well-known
            // quirk of not exposing it back through getMessage() in tests.
            Assert.isNotNull(e, 'A null tool Id must be rejected with an AuraHandledException');
        }
    }

    @IsTest
    static void testRegenerateSchemaEnqueuesAndRunsRegenerationForAValidTool() {
        ApexAgent_Tool__c tool = new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetFieldDetails');
        insert tool;

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        ApexAgentToolSchemaController.regenerateSchema(tool.Id);
        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(jobsBefore + 1, jobsAfter,
            'Invoking the quick action must enqueue exactly one regeneration job');

        ApexAgent_Tool__c reloaded = [SELECT Schema__c FROM ApexAgent_Tool__c WHERE Id = :tool.Id];
        Assert.isNotNull(reloaded.Schema__c, 'The enqueued job must actually regenerate the tool\'s schema');
    }
}
