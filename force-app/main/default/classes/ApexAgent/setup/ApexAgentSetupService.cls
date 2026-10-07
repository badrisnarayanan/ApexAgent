/**
 * Setup for a newly installed org. Creates the starter configuration shipped
 * in the ApexAgentSeedData static resource (LLMs, tools, topics, instructions,
 * agents, MCP servers and the links between them) and assigns the permission
 * sets the product needs.
 *
 * Run it after deploying, from anonymous Apex:
 *
 *     System.debug(ApexAgentSetupService.run().message);
 *
 * Each run first checks the org is ready (see ApexAgentSetupPreflight) and
 * stops, changing nothing, if it is not.
 *
 * Records are only created in an org that has no ApexAgent configuration yet,
 * so running setup again never duplicates records or overwrites an admin's
 * edits. A later run instead finishes what an earlier one could not: it
 * regenerates tool schemas that are still blank, fills in MCP endpoint URLs
 * once the Site is active, and assigns any permission set not yet assigned.
 */
public with sharing class ApexAgentSetupService {

    public static final String ADMIN_PERMISSION_SET = 'ApexAgent_Admin';
    public static final String GUEST_PERMISSION_SET = 'ApexAgent_MCP_Guest';

    public class SetupException extends Exception {}

    /** What a setup run did, for display to the person who ran it. */
    public class Result {
        /** True when the org was not ready and setup changed nothing. The message says what to fix. */
        public Boolean blocked = false;
        public Boolean alreadySetUp = false;
        /** Records created, keyed by a plural label. Empty unless this run created the configuration. */
        public Map<String, Integer> createdCounts = new Map<String, Integer>();
        public String message;
    }

    public static Result run() {
        return run(null);
    }

    /** @param archive the seed data to load, or null to load the shipped static resource when it is needed. */
    @TestVisible
    private static Result run(ApexAgentSeedArchive archive) {
        Result result = new Result();
        List<String> summary = new List<String>();

        ApexAgentSetupPreflight.Report preflight = ApexAgentSetupPreflight.check();
        if (!preflight.blockers.isEmpty()) {
            result.blocked = true;
            result.message = 'Setup did not run. Fix the following, then run setup again. '
                + String.join(preflight.blockers, ' ');
            return result;
        }

        if (hasExistingConfiguration()) {
            result.alreadySetUp = true;
            summary.add('ApexAgent configuration records already exist in this org, so no records were created.');
            summary.addAll(repairIncompleteRecords(preflight));
        } else {
            // A caller that catches the exception (a button, a test) must not be
            // left with half the configuration saved.
            Savepoint beforeCreate = Database.setSavepoint();
            try {
                result.createdCounts = createRecords(archive ?? ApexAgentSeedArchive.fromStaticResource());
            } catch (Exception e) {
                Database.rollback(beforeCreate);
                throw e;
            }
            List<String> counts = new List<String>();
            for (String label : result.createdCounts.keySet()) {
                counts.add(result.createdCounts.get(label) + ' ' + label);
            }
            summary.add('Created ' + String.join(counts, ', ') + '.');
        }

        summary.addAll(assignPermissionSets(preflight));
        summary.addAll(preflight.warnings);
        result.message = String.join(summary, ' ');
        return result;
    }

    // ─── Existing configuration ──────────────────────────────────────────────

    // Setup runs before the installer has any ApexAgent permission set, and must
    // see records owned by other users, so it reads and writes in system mode.
    private static Boolean hasExistingConfiguration() {
        return ![SELECT Id FROM ApexAgent_LLM__c WITH SYSTEM_MODE LIMIT 1].isEmpty()
            || ![SELECT Id FROM ApexAgent_Tool__c WITH SYSTEM_MODE LIMIT 1].isEmpty()
            || ![SELECT Id FROM ApexAgent_Topic__c WITH SYSTEM_MODE LIMIT 1].isEmpty()
            || ![SELECT Id FROM ApexAgent_Agent__c WITH SYSTEM_MODE LIMIT 1].isEmpty()
            || ![SELECT Id FROM ApexAgent_MCP__c WITH SYSTEM_MODE LIMIT 1].isEmpty();
    }

    /**
     * Finishes what an earlier run, or the admin, left incomplete. Only blank
     * generated fields are touched; nothing an admin entered is changed.
     */
    private static List<String> repairIncompleteRecords(ApexAgentSetupPreflight.Report preflight) {
        List<String> summary = new List<String>();

        // Blank when schema generation failed after the tool was created.
        // Long text fields cannot be filtered in SOQL, so blanks are found here.
        Set<Id> toolIdsWithoutSchema = new Set<Id>();
        for (ApexAgent_Tool__c tool : [
            SELECT Schema__c, MCP_Schema__c FROM ApexAgent_Tool__c WHERE Apex_Class_Name__c != null WITH SYSTEM_MODE
        ]) {
            if (String.isBlank(tool.Schema__c) || String.isBlank(tool.MCP_Schema__c)) {
                toolIdsWithoutSchema.add(tool.Id);
            }
        }
        if (!toolIdsWithoutSchema.isEmpty()) {
            System.enqueueJob(new ApexAgentToolSchemaRegenQueueable(toolIdsWithoutSchema));
            summary.add('Regenerating the schema of ' + toolIdsWithoutSchema.size() + ' tool(s) that had none.');
        }

        // Blank when the MCP server was created before the Site was active.
        // Saving the record again makes its trigger work the URL out.
        if (preflight.isSiteActive) {
            List<ApexAgent_MCP__c> mcpsWithoutUrl = [
                SELECT Id FROM ApexAgent_MCP__c WHERE Endpoint_URL__c = null WITH SYSTEM_MODE
            ];
            if (!mcpsWithoutUrl.isEmpty()) {
                update as system mcpsWithoutUrl;
                summary.add('Filled in the endpoint URL of ' + mcpsWithoutUrl.size() + ' MCP server(s).');
            }
        }
        return summary;
    }

    // ─── Records ─────────────────────────────────────────────────────────────

    private static Map<String, Integer> createRecords(ApexAgentSeedArchive archive) {
        Map<String, Object> data = archive.readData();
        List<Object> topicEntries = listOf(data, 'topics');
        List<Object> agentEntries = listOf(data, 'agents');
        List<Object> mcpEntries = listOf(data, 'mcps');

        // Parents first: every list below is saved before anything that points at it.
        Map<String, SObject> llmsByName = buildByKey(ApexAgent_LLM__c.SObjectType, listOf(data, 'llms'), 'Name');
        Map<String, SObject> toolsByClass = buildByKey(ApexAgent_Tool__c.SObjectType, listOf(data, 'tools'), 'Apex_Class_Name__c');
        Map<String, SObject> topicsByApiName = buildByKey(ApexAgent_Topic__c.SObjectType, topicEntries, 'Topic_API_Name__c');
        Map<String, SObject> mcpsByApiName = buildByKey(ApexAgent_MCP__c.SObjectType, mcpEntries, 'MCP_API_Name__c');
        insert as system llmsByName.values();
        insert as system toolsByClass.values();
        insert as system topicsByApiName.values();
        insert as system mcpsByApiName.values();

        List<ApexAgent_Agent__c> agents = new List<ApexAgent_Agent__c>();
        for (Object entry : agentEntries) {
            Map<String, Object> agentEntry = (Map<String, Object>) entry;
            ApexAgent_Agent__c agent = (ApexAgent_Agent__c) build(ApexAgent_Agent__c.SObjectType, agentEntry);
            agent.LLM__c = resolve(llmsByName, (String) agentEntry.get('llm'), 'LLM', 'agent ' + agent.Name);
            agents.add(agent);
        }
        insert as system agents;

        List<ApexAgent_Instruction__c> instructions = new List<ApexAgent_Instruction__c>();
        List<ApexAgent_Topic_Tool_Map__c> topicTools = new List<ApexAgent_Topic_Tool_Map__c>();
        for (Object entry : topicEntries) {
            Map<String, Object> topicEntry = (Map<String, Object>) entry;
            String topicApiName = (String) topicEntry.get('Topic_API_Name__c');
            Id topicId = topicsByApiName.get(topicApiName.toLowerCase()).Id;

            for (Object child : listOf(topicEntry, 'instructions')) {
                Map<String, Object> instructionEntry = (Map<String, Object>) child;
                ApexAgent_Instruction__c instruction =
                    (ApexAgent_Instruction__c) build(ApexAgent_Instruction__c.SObjectType, instructionEntry);
                instruction.Topic__c = topicId;
                instruction.Instruction__c = archive.readText((String) instructionEntry.get('file'));
                instructions.add(instruction);
            }
            for (Object child : listOf(topicEntry, 'tools')) {
                Map<String, Object> link = (Map<String, Object>) child;
                ApexAgent_Topic_Tool_Map__c topicTool =
                    (ApexAgent_Topic_Tool_Map__c) build(ApexAgent_Topic_Tool_Map__c.SObjectType, link);
                topicTool.Topic__c = topicId;
                topicTool.Tool__c = resolve(toolsByClass, (String) link.get('tool'), 'tool', 'topic ' + topicApiName);
                topicTools.add(topicTool);
            }
        }

        List<ApexAgent_Topic_Map__c> agentTopics = new List<ApexAgent_Topic_Map__c>();
        for (Integer i = 0; i < agentEntries.size(); i++) {
            for (Object child : listOf((Map<String, Object>) agentEntries[i], 'topics')) {
                Map<String, Object> link = (Map<String, Object>) child;
                ApexAgent_Topic_Map__c agentTopic =
                    (ApexAgent_Topic_Map__c) build(ApexAgent_Topic_Map__c.SObjectType, link);
                agentTopic.Agent__c = agents[i].Id;
                agentTopic.Topic__c = resolve(topicsByApiName, (String) link.get('topic'), 'topic', 'agent ' + agents[i].Name);
                agentTopics.add(agentTopic);
            }
        }

        List<ApexAgent_MCP_Tool_Map__c> mcpTools = new List<ApexAgent_MCP_Tool_Map__c>();
        for (Object entry : mcpEntries) {
            Map<String, Object> mcpEntry = (Map<String, Object>) entry;
            String mcpApiName = (String) mcpEntry.get('MCP_API_Name__c');
            for (Object child : listOf(mcpEntry, 'tools')) {
                Map<String, Object> link = (Map<String, Object>) child;
                ApexAgent_MCP_Tool_Map__c mcpTool =
                    (ApexAgent_MCP_Tool_Map__c) build(ApexAgent_MCP_Tool_Map__c.SObjectType, link);
                mcpTool.MCP__c = mcpsByApiName.get(mcpApiName.toLowerCase()).Id;
                mcpTool.Tool__c = resolve(toolsByClass, (String) link.get('tool'), 'tool', 'MCP server ' + mcpApiName);
                mcpTools.add(mcpTool);
            }
        }

        insert as system instructions;
        insert as system topicTools;
        insert as system agentTopics;
        insert as system mcpTools;

        return new Map<String, Integer>{
            'LLMs' => llmsByName.size(),
            'tools' => toolsByClass.size(),
            'topics' => topicsByApiName.size(),
            'instructions' => instructions.size(),
            'agents' => agents.size(),
            'MCP servers' => mcpsByApiName.size(),
            'links' => topicTools.size() + agentTopics.size() + mcpTools.size()
        };
    }

    /**
     * Builds one unsaved record per entry, keyed by the field other entries refer
     * to it by. Keys are lower-cased because the org's unique fields ignore case:
     * two entries differing only by case would be rejected when saved.
     */
    private static Map<String, SObject> buildByKey(SObjectType objectType, List<Object> entries, String keyField) {
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        for (Object entry : entries) {
            SObject record = build(objectType, (Map<String, Object>) entry);
            String key = (String) record.get(keyField);
            if (String.isBlank(key)) {
                throw new SetupException('A ' + objectType + ' entry in the seed data has no ' + keyField + '.');
            }
            if (recordsByKey.containsKey(key.toLowerCase())) {
                throw new SetupException('The seed data has two ' + objectType + ' entries with ' + keyField + ' "' + key + '".');
            }
            recordsByKey.put(key.toLowerCase(), record);
        }
        return recordsByKey;
    }

    /**
     * Copies an entry's field values onto a new record. Keys that are field API
     * names ("Name" or ending in "__c") are fields; every other key describes
     * how the entry links to other entries and is handled by the caller.
     */
    private static SObject build(SObjectType objectType, Map<String, Object> entry) {
        SObject record = objectType.newSObject();
        Map<String, SObjectField> fieldsByName = objectType.getDescribe().fields.getMap();
        for (String key : entry.keySet()) {
            if (key != 'Name' && !key.endsWith('__c')) {
                continue;
            }
            SObjectField field = fieldsByName.get(key.toLowerCase());
            if (field == null) {
                throw new SetupException('The seed data sets ' + key + ', which is not a field on ' + objectType + '.');
            }
            record.put(field, toFieldValue(field, entry.get(key)));
        }
        return record;
    }

    /** JSON numbers arrive as Integer or Decimal; number fields only accept the type they store. */
    private static Object toFieldValue(SObjectField field, Object value) {
        if (value == null) {
            return null;
        }
        switch on field.getDescribe().getType() {
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(String.valueOf(value));
            }
            when INTEGER {
                return Integer.valueOf(String.valueOf(value));
            }
            when else {
                return value;
            }
        }
    }

    private static Id resolve(Map<String, SObject> recordsByKey, String key, String kind, String referrer) {
        SObject record = key == null ? null : recordsByKey.get(key.toLowerCase());
        if (record == null) {
            throw new SetupException(
                'The seed data for ' + referrer + ' refers to ' + kind + ' "' + key + '", which is not defined in the seed data.'
            );
        }
        return record.Id;
    }

    private static List<Object> listOf(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return value == null ? new List<Object>() : (List<Object>) value;
    }

    // ─── Permission sets ─────────────────────────────────────────────────────

    private static List<String> assignPermissionSets(ApexAgentSetupPreflight.Report preflight) {
        List<String> summary = new List<String>();

        System.enqueueJob(new ApexAgentSetupPermissionQueueable(UserInfo.getUserId(), ADMIN_PERMISSION_SET));
        summary.add('Assigning ' + ADMIN_PERMISSION_SET + ' to you.');

        // When there is no guest user the preflight warnings already say why.
        if (preflight.guestUserId != null) {
            System.enqueueJob(new ApexAgentSetupPermissionQueueable(preflight.guestUserId, GUEST_PERMISSION_SET));
            summary.add('Assigning ' + GUEST_PERMISSION_SET + ' to the MCP Site guest user.');
        }
        summary.add('Check Setup > Apex Jobs if an assignment does not appear.');
        return summary;
    }
}
