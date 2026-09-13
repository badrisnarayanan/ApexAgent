/**
 * Regenerates ApexAgent_Tool__c.Schema__c for a set of tool records by reflecting
 * on each tool's Apex Action (ApexAgentToolSchemaBuilder.buildDefinitions).
 *
 * Runs only in async context because ApexAgentSymbolTableService resolves nested
 * Apex-defined parameter types via a same-org Tooling API self-callout, and no
 * callouts are allowed directly from a trigger. Enqueued from two places:
 *  - ApexAgentToolTriggerHandler, after insert or after Apex_Class_Name__c changes
 *  - ApexAgentToolSchemaController.regenerateSchema(), from the record page's
 *    "Regenerate Schema" quick action
 *
 * A tool whose class fails to build (invalid/missing Apex class, no
 * @InvocableMethod, a Tooling API failure, or a definition too large for
 * Schema__c) is left untouched — Schema__c keeps whatever it last held rather
 * than being overwritten with a broken value — and every admin is emailed once
 * per run listing the affected Apex class names.
 */
public with sharing class ApexAgentToolSchemaRegenQueueable implements Queueable, Database.AllowsCallouts {

    // Read from the field itself rather than hardcoded, so it can never drift
    // out of sync with Schema__c's actual declared length.
    private static final Integer MAX_SCHEMA_LENGTH = ApexAgent_Tool__c.Schema__c.getDescribe().getLength();

    private final Set<Id> toolIds;

    public ApexAgentToolSchemaRegenQueueable(Set<Id> toolIds) {
        this.toolIds = toolIds;
    }

    public void execute(QueueableContext ctx) {
        List<ApexAgent_Tool__c> tools = [
            SELECT Id, Apex_Class_Name__c
            FROM ApexAgent_Tool__c
            WHERE Id IN :toolIds
        ];
        if (tools.isEmpty()) {
            return;
        }

        Map<String, Id> toolIdByClassName = new Map<String, Id>();
        for (ApexAgent_Tool__c tool : tools) {
            if (String.isNotBlank(tool.Apex_Class_Name__c)) {
                toolIdByClassName.put(tool.Apex_Class_Name__c, tool.Id);
            }
        }

        Map<String, Map<String, Object>> definitionsByClass = safelyBuildDefinitions(toolIdByClassName.keySet());

        List<ApexAgent_Tool__c> toolsToUpdate = new List<ApexAgent_Tool__c>();
        List<String> classNamesToUpdate = new List<String>();
        List<String> failedClassNames = new List<String>();

        for (String className : toolIdByClassName.keySet()) {
            String schemaJson = serializeIfWithinLimit(definitionsByClass.get(className));
            if (schemaJson == null) {
                failedClassNames.add(className);
                continue;
            }
            toolsToUpdate.add(new ApexAgent_Tool__c(Id = toolIdByClassName.get(className), Schema__c = schemaJson));
            classNamesToUpdate.add(className);
        }

        failedClassNames.addAll(updateAndCollectDmlFailures(toolsToUpdate, classNamesToUpdate));

        if (!failedClassNames.isEmpty()) {
            notifyAdminsOfFailure(failedClassNames);
        }
    }

    /**
     * Database.update(.., false) so one record's DML failure (a validation rule,
     * or a lock conflict with another regeneration job already touching the same
     * record) never loses every other successfully-built schema in the same
     * batch — each DML failure is folded into the same admin-notification path
     * as a build failure, rather than throwing uncaught out of execute().
     */
    private List<String> updateAndCollectDmlFailures(List<ApexAgent_Tool__c> toolsToUpdate, List<String> classNamesToUpdate) {
        List<String> failures = new List<String>();
        if (toolsToUpdate.isEmpty()) {
            return failures;
        }

        List<Database.SaveResult> results = Database.update(toolsToUpdate, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failures.add(classNamesToUpdate[i]);
                System.debug(LoggingLevel.WARN,
                    'Failed to save regenerated schema for ' + classNamesToUpdate[i] + ': ' + results[i].getErrors());
            }
        }
        return failures;
    }

    /**
     * A failure resolving one class's nested types (Tooling API callout error)
     * would otherwise propagate out of buildDefinitions and fail the whole batch —
     * every class in this run is treated as failed instead, preserving the
     * "never overwrite a good schema with a broken one" guarantee.
     */
    private Map<String, Map<String, Object>> safelyBuildDefinitions(Set<String> classNames) {
        try {
            return ApexAgentToolSchemaBuilder.buildDefinitions(classNames);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Tool schema regeneration failed for the whole batch: ' + e.getMessage());
            return new Map<String, Map<String, Object>>();
        }
    }

    /**
     * Pretty-printed so an admin can actually read Schema__c on the record page —
     * this only affects what's stored. ApexAgentLLMClient re-serializes the whole
     * request body compact at call time regardless of how the tool definition was
     * stored, so this has no effect on the wire payload sent to the LLM.
     * A truncated definition is strictly worse than a blank field, so treated as
     * a failure too — note the length check is against the pretty-printed size,
     * which is larger than the compact form for the same definition.
     */
    private String serializeIfWithinLimit(Map<String, Object> definition) {
        if (definition == null) {
            return null;
        }
        String schemaJson = JSON.serializePretty(definition);
        return schemaJson.length() <= MAX_SCHEMA_LENGTH ? schemaJson : null;
    }

    private void notifyAdminsOfFailure(List<String> failedClassNames) {
        List<String> adminEmails = queryActiveAdminEmails();
        if (adminEmails.isEmpty()) {
            return;
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(adminEmails);
        email.setSubject('ApexAgent: tool schema generation failed');
        email.setPlainTextBody(
            'Schema generation failed for the following Apex Class Name(s) on Agent Tool records. '
            + 'Their Schema__c field was left unchanged, so they may be missing from the agent\'s '
            + 'available tools until this is fixed and the schema is regenerated:\n\n'
            + String.join(failedClassNames, '\n')
            + '\n\nCheck that each Apex class is deployed, valid, and exposes an @InvocableMethod, '
            + 'then use the Regenerate Schema quick action on the affected Agent Tool record(s).'
        );

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send tool schema failure email: ' + e.getMessage());
        }
    }

    /**
     * A user can gain ApexAgent_Admin either by direct assignment or through a
     * Permission Set Group that includes it as a component — a group assignment
     * doesn't show up under PermissionSet.Name, so its member groups are
     * resolved first and matched on PermissionSetGroupId too.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private List<String> queryActiveAdminEmails() {
        Set<Id> permissionSetGroupIds = new Set<Id>();
        for (PermissionSetGroupComponent psgc : [
            SELECT PermissionSetGroupId
            FROM PermissionSetGroupComponent
            WHERE PermissionSet.Name = 'ApexAgent_Admin'
        ]) {
            permissionSetGroupIds.add(psgc.PermissionSetGroupId);
        }

        Set<String> emails = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT Assignee.Email
            FROM PermissionSetAssignment
            WHERE Assignee.IsActive = true
              AND (PermissionSet.Name = 'ApexAgent_Admin' OR PermissionSetGroupId IN :permissionSetGroupIds)
        ]) {
            if (String.isNotBlank(psa.Assignee.Email)) {
                emails.add(psa.Assignee.Email);
            }
        }
        return new List<String>(emails);
    }
}
