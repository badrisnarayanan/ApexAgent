/**
 * Tests for org setup: ApexAgentSetupService, its readiness checks, the seed
 * archive it reads and the permission set assignment job it enqueues.
 *
 * Most tests build their own small seed archive so they do not depend on what
 * the shipped ApexAgentSeedData resource currently contains; one test loads
 * the shipped resource to prove it is valid.
 */
@IsTest
private class ApexAgentSetupServiceTest {

    private static final String INSTRUCTION_FILE = 'instructions/be-brief.md';
    private static final String INSTRUCTION_TEXT = '# Be brief\nAnswer in "one" sentence — always.';

    @IsTest
    static void testRunCreatesLinkedRecordsOnceThenOnlyRepairs() {
        ApexAgentSetupPreflight.probe = new StubProbe(null);
        ApexAgentSeedArchive archive = archiveOf(validSeed(), new Map<String, String>{ INSTRUCTION_FILE => INSTRUCTION_TEXT });

        Test.startTest();
        ApexAgentSetupService.Result first = ApexAgentSetupService.run(archive);
        Integer jobsAfterFirstRun = Limits.getQueueableJobs();
        ApexAgentSetupService.Result second = ApexAgentSetupService.run(archive);
        Test.stopTest();

        Assert.isFalse(first.blocked, 'A ready org should not be blocked: ' + first.message);
        Assert.isFalse(first.alreadySetUp, 'An org with no configuration should be set up');
        Assert.areEqual(1, first.createdCounts.get('LLMs'), 'LLM count');
        Assert.areEqual(2, first.createdCounts.get('tools'), 'Tool count');
        Assert.areEqual(1, first.createdCounts.get('topics'), 'Topic count');
        Assert.areEqual(1, first.createdCounts.get('instructions'), 'Instruction count');
        Assert.areEqual(1, first.createdCounts.get('agents'), 'Agent count');
        Assert.areEqual(1, first.createdCounts.get('MCP servers'), 'MCP server count');
        Assert.areEqual(4, first.createdCounts.get('links'), 'Two topic-tool links, one agent-topic link, one MCP-tool link');
        Assert.isTrue(first.message.contains('Created 1 LLMs'), 'The message should summarise what was created: ' + first.message);
        Assert.isTrue(first.message.contains(ApexAgentSetupService.ADMIN_PERMISSION_SET), 'The message should name the admin permission set');
        Assert.isTrue(jobsAfterFirstRun >= 2, 'Setup should enqueue the tool schema job and at least the admin permission set job');

        ApexAgent_LLM__c llm = [SELECT Name, Output_Token_Cost_M__c, Cached_Input_Token_Cost_M__c, Supports_Reasoning__c FROM ApexAgent_LLM__c];
        Assert.areEqual(1.875, llm.Output_Token_Cost_M__c, 'A decimal JSON number should be saved to a currency field');
        Assert.areEqual(0, llm.Cached_Input_Token_Cost_M__c, 'A whole JSON number should be saved to a currency field');
        Assert.isTrue(llm.Supports_Reasoning__c, 'Checkbox value should be copied');

        ApexAgent_Agent__c agent = [SELECT Name, LLM__c, Max_Tokens__c, Conversation_Depth__c FROM ApexAgent_Agent__c];
        Assert.areEqual(llm.Id, agent.LLM__c, 'The agent should point at the LLM it names');
        Assert.areEqual(1000, agent.Max_Tokens__c, 'A whole JSON number should be saved to a number field');

        ApexAgent_Topic__c topic = [SELECT Id FROM ApexAgent_Topic__c];
        ApexAgent_Instruction__c instruction = [SELECT Topic__c, Instruction__c, Order__c, Active__c FROM ApexAgent_Instruction__c];
        Assert.areEqual(topic.Id, instruction.Topic__c, 'The instruction should belong to its topic');
        Assert.areEqual(INSTRUCTION_TEXT, instruction.Instruction__c, 'Instruction text should come from its file, unchanged');
        Assert.areEqual(1, instruction.Order__c, 'Instruction order should be copied');

        Map<String, Boolean> topicToolActiveByClass = new Map<String, Boolean>();
        for (ApexAgent_Topic_Tool_Map__c link : [SELECT Tool__r.Apex_Class_Name__c, Active__c, Unique_Key__c FROM ApexAgent_Topic_Tool_Map__c WHERE Topic__c = :topic.Id]) {
            topicToolActiveByClass.put(link.Tool__r.Apex_Class_Name__c, link.Active__c);
            Assert.isNotNull(link.Unique_Key__c, 'The org should generate the link key; it is never shipped');
        }
        Assert.areEqual(true, topicToolActiveByClass.get('ApexAgentGetObjectApiName'), 'Active link should stay active');
        Assert.areEqual(false, topicToolActiveByClass.get('ApexAgentUpsertRecords'), 'Inactive link should stay inactive');

        ApexAgent_Topic_Map__c agentTopic = [SELECT Agent__c, Topic__c FROM ApexAgent_Topic_Map__c];
        Assert.areEqual(agent.Id, agentTopic.Agent__c, 'Agent-topic link should point at the agent');
        Assert.areEqual(topic.Id, agentTopic.Topic__c, 'Agent-topic link should point at the topic');

        ApexAgent_MCP_Tool_Map__c mcpTool = [SELECT MCP__r.MCP_API_Name__c, Tool__r.Apex_Class_Name__c FROM ApexAgent_MCP_Tool_Map__c];
        Assert.areEqual('default', mcpTool.MCP__r.MCP_API_Name__c, 'MCP-tool link should point at the MCP server');
        Assert.areEqual('ApexAgentGetObjectApiName', mcpTool.Tool__r.Apex_Class_Name__c, 'MCP-tool link should point at the tool');

        Assert.isTrue(second.alreadySetUp, 'A second run should detect the existing configuration');
        Assert.isTrue(second.createdCounts.isEmpty(), 'A second run should create nothing');
        Assert.isTrue(second.message.contains('already exist'), 'The message should say why nothing was created: ' + second.message);
        Assert.isTrue(second.message.contains('Regenerating the schema of 2 tool(s)'),
            'A second run should retry schema generation for tools that still have none: ' + second.message);
        Assert.areEqual(2, [SELECT COUNT() FROM ApexAgent_Tool__c], 'A second run must not duplicate tools');
        Assert.areEqual(1, [SELECT COUNT() FROM ApexAgent_Instruction__c], 'A second run must not duplicate instructions');
    }

    @IsTest
    static void testInvalidSeedDataFailsClearlyAndSavesNothing() {
        ApexAgentSetupPreflight.probe = new StubProbe(null);
        Map<String, String> files = new Map<String, String>{ INSTRUCTION_FILE => INSTRUCTION_TEXT };

        try {
            new ApexAgentSeedArchive(Blob.valueOf('not a zip'));
            Assert.fail('Bytes that are not a zip should be rejected');
        } catch (ApexAgentSeedArchive.SeedArchiveException e) {
            Assert.isTrue(e.getMessage().contains('not a readable zip'), e.getMessage());
        }

        Compression.ZipWriter noDataFile = new Compression.ZipWriter();
        noDataFile.addEntry('readme.txt', Blob.valueOf('nothing here'));
        assertSetupFails(new ApexAgentSeedArchive(noDataFile.getArchive()), 'no file named "data.json"');

        Compression.ZipWriter brokenJson = new Compression.ZipWriter();
        brokenJson.addEntry(ApexAgentSeedArchive.DATA_ENTRY, Blob.valueOf('{ not json'));
        assertSetupFails(new ApexAgentSeedArchive(brokenJson.getArchive()), 'not a valid JSON object');

        Map<String, Object> unknownField = validSeed();
        firstEntry(unknownField, 'llms').put('Not_A_Field__c', 'x');
        assertSetupFails(archiveOf(unknownField, files), 'Not_A_Field__c, which is not a field');

        Map<String, Object> duplicateTool = validSeed();
        ((List<Object>) duplicateTool.get('tools')).add(new Map<String, Object>{ 'Name' => 'Again', 'Apex_Class_Name__c' => 'ApexAgentUpsertRecords' });
        assertSetupFails(archiveOf(duplicateTool, files), 'two ApexAgent_Tool__c entries');

        Map<String, Object> sameKeyDifferentCase = validSeed();
        ((List<Object>) sameKeyDifferentCase.get('mcps')).add(new Map<String, Object>{ 'Name' => 'Again', 'MCP_API_Name__c' => 'DEFAULT' });
        assertSetupFails(archiveOf(sameKeyDifferentCase, files), 'two ApexAgent_MCP__c entries');

        Map<String, Object> unknownLlm = validSeed();
        firstEntry(unknownLlm, 'agents').put('llm', 'No Such LLM');
        assertSetupFails(archiveOf(unknownLlm, files), 'refers to LLM "No Such LLM"');

        Map<String, Object> unknownTool = validSeed();
        firstEntry(unknownTool, 'mcps').put('tools', new List<Object>{ new Map<String, Object>{ 'tool' => 'NoSuchTool', 'Active__c' => true } });
        assertSetupFails(archiveOf(unknownTool, files), 'refers to tool "NoSuchTool"');

        assertSetupFails(archiveOf(validSeed(), new Map<String, String>()), 'no file named "' + INSTRUCTION_FILE + '"');

        Assert.areEqual(0, [SELECT COUNT() FROM ApexAgent_LLM__c], 'A failed setup must leave no partial records behind');
        Assert.areEqual(0, [SELECT COUNT() FROM ApexAgent_Tool__c], 'A failed setup must leave no partial records behind');
    }

    @IsTest
    static void testShippedSeedDataIsValid() {
        ApexAgentSetupPreflight.probe = new StubProbe(null);
        // Lets the schema job run for real, so a shipped tool that cannot produce a schema fails this test.
        ApexAgentSymbolTableTypes.ToolingQueryResult noSymbolTables = new ApexAgentSymbolTableTypes.ToolingQueryResult();
        noSymbolTables.records = new List<ApexAgentSymbolTableTypes.ApexClassRecord>();
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, JSON.serialize(noSymbolTables)));

        Test.startTest();
        ApexAgentSetupService.Result result = ApexAgentSetupService.run();
        Test.stopTest();

        Assert.isFalse(result.blocked, 'A ready org should not be blocked: ' + result.message);
        Assert.isFalse(result.alreadySetUp, 'The shipped seed data should load into an empty org');
        Assert.isTrue(result.createdCounts.get('tools') > 0, 'The shipped seed data should define tools');
        Assert.isTrue(result.createdCounts.get('agents') > 0, 'The shipped seed data should define an agent');

        Set<String> toolClassNames = new Set<String>();
        for (ApexAgent_Tool__c tool : [SELECT Apex_Class_Name__c, Schema__c, MCP_Schema__c FROM ApexAgent_Tool__c]) {
            toolClassNames.add(tool.Apex_Class_Name__c);
            Assert.isTrue(String.isNotBlank(tool.Schema__c), 'Shipped tool ' + tool.Apex_Class_Name__c + ' produced no chat schema');
            Assert.isTrue(String.isNotBlank(tool.MCP_Schema__c), 'Shipped tool ' + tool.Apex_Class_Name__c + ' produced no MCP schema');
        }
        Assert.areEqual(toolClassNames.size(), [SELECT COUNT() FROM ApexClass WHERE Name IN :toolClassNames],
            'Every shipped tool must name an Apex class that exists: ' + toolClassNames);
        Assert.areEqual(0, [SELECT COUNT() FROM ApexAgent_Instruction__c WHERE Active__c = true AND Order__c = null],
            'Every shipped active instruction needs an order');
        for (ApexAgent_Instruction__c instruction : [SELECT Name, Instruction__c FROM ApexAgent_Instruction__c]) {
            Assert.isTrue(String.isNotBlank(instruction.Instruction__c), 'Shipped instruction "' + instruction.Name + '" has no text');
        }
    }

    @IsTest
    static void testUnreadyOrgIsBlockedBeforeAnythingIsCreated() {
        ApexAgentSetupPreflight.probe = new StubProbe('no Remote Site Setting allows it');
        ApexAgentSeedArchive archive = archiveOf(validSeed(), new Map<String, String>{ INSTRUCTION_FILE => INSTRUCTION_TEXT });

        Test.startTest();
        ApexAgentSetupService.Result result = ApexAgentSetupService.run(archive);
        Integer jobsEnqueued = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.isTrue(result.blocked, 'Setup must not run without a Remote Site Setting');
        Assert.isTrue(result.message.contains('Remote Site Settings'), 'The message should say where to fix it: ' + result.message);
        Assert.isTrue(result.message.contains(URL.getOrgDomainUrl().toExternalForm()), 'The message should give the exact URL to add: ' + result.message);
        Assert.areEqual(0, jobsEnqueued, 'A blocked setup must not start any job');
        Assert.areEqual(0, [SELECT COUNT() FROM ApexAgent_Tool__c], 'A blocked setup must create nothing');

        // The real probe: allowed, refused for lack of a Remote Site Setting, and failing for another reason.
        ApexAgentSetupPreflight.RemoteSiteProbe httpProbe = new ApexAgentSetupPreflight.HttpRemoteSiteProbe();
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, '{}'));
        Assert.isNull(httpProbe.findProblem('https://example.my.salesforce.com'), 'A completed callout means the domain is allowed');
        Test.setMock(HttpCalloutMock.class, new FailingCalloutMock('Unauthorized endpoint, please check Setup->Security->Remote site settings.'));
        Assert.areEqual('no Remote Site Setting allows it', httpProbe.findProblem('https://example.my.salesforce.com'),
            'A refused endpoint should be reported as a missing Remote Site Setting');
        Test.setMock(HttpCalloutMock.class, new FailingCalloutMock('Read timed out'));
        Assert.areEqual('Read timed out', httpProbe.findProblem('https://example.my.salesforce.com'),
            'Any other callout failure should be reported as it is');
    }

    @IsTest
    static void testPermissionSetJobAssignsOnceAndRejectsUnknownPermissionSet() {
        Id userId = UserInfo.getUserId();
        String permissionSetName = ApexAgentSetupService.GUEST_PERMISSION_SET;
        delete [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSet.Name = :permissionSetName];

        ApexAgentSetupPermissionQueueable job = new ApexAgentSetupPermissionQueueable(userId, permissionSetName);
        job.execute(null);
        job.execute(null);

        Assert.areEqual(1, [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSet.Name = :permissionSetName],
            'The permission set should be assigned exactly once, however many times the job runs');

        try {
            new ApexAgentSetupPermissionQueueable(userId, 'No_Such_Permission_Set').execute(null);
            Assert.fail('An unknown permission set should be rejected');
        } catch (ApexAgentSetupService.SetupException e) {
            Assert.isTrue(e.getMessage().contains('No_Such_Permission_Set was not found'), e.getMessage());
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private class StubProbe implements ApexAgentSetupPreflight.RemoteSiteProbe {
        private final String problem;
        StubProbe(String problem) {
            this.problem = problem;
        }
        public String findProblem(String orgDomainUrl) {
            return problem;
        }
    }

    private class FailingCalloutMock implements HttpCalloutMock {
        private final String message;
        FailingCalloutMock(String message) {
            this.message = message;
        }
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException(message);
        }
    }

    private static Map<String, Object> validSeed() {
        return new Map<String, Object>{
            'llms' => new List<Object>{ new Map<String, Object>{
                'Name' => 'Test LLM', 'Model_API_Name__c' => 'test/model', 'Family__c' => 'Test',
                'Named_Credential__c' => 'TestCredential', 'Supports_Reasoning__c' => true,
                'Output_Token_Cost_M__c' => 1.875, 'Cached_Input_Token_Cost_M__c' => 0
            } },
            'tools' => new List<Object>{
                new Map<String, Object>{ 'Name' => 'Get Object API Name', 'Apex_Class_Name__c' => 'ApexAgentGetObjectApiName', 'Modifies_Salesforce_Data__c' => false },
                new Map<String, Object>{ 'Name' => 'Upsert Records', 'Apex_Class_Name__c' => 'ApexAgentUpsertRecords', 'Modifies_Salesforce_Data__c' => true }
            },
            'topics' => new List<Object>{ new Map<String, Object>{
                'Name' => 'Test Topic', 'Topic_API_Name__c' => 'test_topic',
                'instructions' => new List<Object>{ new Map<String, Object>{
                    'Name' => 'Be Brief', 'Order__c' => 1, 'Active__c' => true, 'file' => INSTRUCTION_FILE
                } },
                'tools' => new List<Object>{
                    new Map<String, Object>{ 'tool' => 'ApexAgentGetObjectApiName', 'Active__c' => true },
                    new Map<String, Object>{ 'tool' => 'ApexAgentUpsertRecords', 'Active__c' => false }
                }
            } },
            'agents' => new List<Object>{ new Map<String, Object>{
                'Name' => 'Test Agent', 'Max_Tokens__c' => 1000, 'Conversation_Depth__c' => 15, 'llm' => 'Test LLM',
                'topics' => new List<Object>{ new Map<String, Object>{ 'topic' => 'test_topic', 'Order__c' => 1, 'Active__c' => true } }
            } },
            'mcps' => new List<Object>{ new Map<String, Object>{
                'Name' => 'Test MCP Server', 'MCP_API_Name__c' => 'default', 'Active__c' => true,
                'tools' => new List<Object>{ new Map<String, Object>{ 'tool' => 'ApexAgentGetObjectApiName', 'Active__c' => true } }
            } }
        };
    }

    private static Map<String, Object> firstEntry(Map<String, Object> seed, String listName) {
        return (Map<String, Object>) ((List<Object>) seed.get(listName))[0];
    }

    private static ApexAgentSeedArchive archiveOf(Map<String, Object> seed, Map<String, String> files) {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry(ApexAgentSeedArchive.DATA_ENTRY, Blob.valueOf(JSON.serialize(seed)));
        for (String fileName : files.keySet()) {
            writer.addEntry(fileName, Blob.valueOf(files.get(fileName)));
        }
        return new ApexAgentSeedArchive(writer.getArchive());
    }

    private static void assertSetupFails(ApexAgentSeedArchive archive, String expectedMessagePart) {
        try {
            ApexAgentSetupService.run(archive);
            Assert.fail('Setup should have failed with: ' + expectedMessagePart);
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(expectedMessagePart),
                'Expected a message containing "' + expectedMessagePart + '" but got: ' + e.getMessage());
        }
    }
}
