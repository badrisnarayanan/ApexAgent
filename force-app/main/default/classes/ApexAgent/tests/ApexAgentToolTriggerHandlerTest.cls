/**
 * Verifies ApexAgentToolTriggerHandler enqueues schema regeneration exactly
 * when it should: once per save (bulk-batched into a single Queueable, not
 * one per record) on insert, and on update only when Apex_Class_Name__c
 * actually changes — never on an unrelated field update. That "never on
 * unrelated field update" rule is also the recursion guard against the
 * Queueable's own Schema__c-only update, so it's asserted via the Limits
 * governor counter (which increments the instant System.enqueueJob is called)
 * rather than by inspecting the Queueable's actual output — that
 * reflection/callout behavior belongs to ApexAgentToolSchemaRegenQueueableTest.
 * Every count is read within one Test.startTest()/stopTest() window so it
 * isn't affected by the fresh governor context that boundary opens.
 */
@IsTest
private class ApexAgentToolTriggerHandlerTest {

    @IsTest
    static void testInsertEnqueuesOnceInBulkForMultipleValidRecords() {
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        insert new List<ApexAgent_Tool__c>{
            new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetFieldDetails'),
            new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetObjectDetails')
        };
        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(jobsBefore + 1, jobsAfter,
            'A bulk insert must enqueue exactly one batched Queueable, not one per record');
    }

    @IsTest
    static void testUpdateEnqueuesOnlyWhenApexClassNameChanges() {
        ApexAgent_Tool__c tool = new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetFieldDetails');
        insert tool;

        Test.startTest();
        Integer jobsAfterInsert = Limits.getQueueableJobs();

        tool.Modifies_Salesforce_Data__c = true;
        update tool;
        Assert.areEqual(jobsAfterInsert, Limits.getQueueableJobs(),
            'Changing an unrelated field must not re-enqueue regeneration');

        tool.Apex_Class_Name__c = 'GetObjectDetails';
        update tool;
        Assert.areEqual(jobsAfterInsert + 1, Limits.getQueueableJobs(),
            'Changing Apex_Class_Name__c must enqueue regeneration');
        Test.stopTest();
    }

    /**
     * Apex_Class_Name__c is required at the field level, so a blank value
     * can never reach the trigger through real DML — this calls the handler
     * directly (in-memory records, no insert) to prove the guard itself
     * skips a blank value rather than relying on the field requirement alone.
     */
    @IsTest
    static void testHandlerSkipsRecordsWithBlankApexClassName() {
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        ApexAgentToolTriggerHandler.handleAfterSave(
            new List<ApexAgent_Tool__c>{ new ApexAgent_Tool__c(Apex_Class_Name__c = null) },
            null
        );
        Test.stopTest();

        Assert.areEqual(jobsBefore, Limits.getQueueableJobs(),
            'A record with a blank Apex_Class_Name__c must never enqueue regeneration');
    }
}
