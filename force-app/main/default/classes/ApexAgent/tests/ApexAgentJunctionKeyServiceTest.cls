/**
 * Verifies Unique_Key__c maintenance and duplicate rejection on the three
 * junction objects, plus the validation rules guarding agent setup data.
 */
@IsTest
private class ApexAgentJunctionKeyServiceTest {

    private static ApexAgent_LLM__c buildLlm(Boolean supportsReasoning) {
        return new ApexAgent_LLM__c(
            Name                     = 'Test LLM',
            Model_API_Name__c        = 'test-model',
            Family__c                = 'Anthropic',
            Named_Credential__c      = 'TestCred',
            Chat_Completions_Path__c = '/v1/messages',
            Supports_Reasoning__c    = supportsReasoning
        );
    }

    private static ApexAgent_Tool__c buildTool(String className) {
        return new ApexAgent_Tool__c(Name = className, Apex_Class_Name__c = className);
    }

    private static String firstError(Database.SaveResult result) {
        Assert.isFalse(result.isSuccess(), 'Save was expected to fail');
        return result.getErrors()[0].getMessage();
    }

    @IsTest
    static void testKeysPopulatedAndDuplicatesRejectedOnAllJunctions() {
        ApexAgent_LLM__c llm = buildLlm(false);
        insert llm;
        ApexAgent_Agent__c agent = new ApexAgent_Agent__c(Name = 'Agent', LLM__c = llm.Id, Max_Tokens__c = 1000);
        insert agent;
        ApexAgent_Topic__c topic = new ApexAgent_Topic__c(Name = 'Topic', Topic_API_Name__c = 'topic');
        insert topic;
        ApexAgent_Tool__c tool = buildTool('FakeJunctionTool');
        insert tool;
        ApexAgent_MCP__c mcp = new ApexAgent_MCP__c(Name = 'Server', MCP_API_Name__c = 'junctionserver');
        insert mcp;

        ApexAgent_Topic_Map__c topicMap = new ApexAgent_Topic_Map__c(Agent__c = agent.Id, Topic__c = topic.Id);
        ApexAgent_Topic_Tool_Map__c topicToolMap = new ApexAgent_Topic_Tool_Map__c(Topic__c = topic.Id, Tool__c = tool.Id);
        ApexAgent_MCP_Tool_Map__c mcpToolMap = new ApexAgent_MCP_Tool_Map__c(MCP__c = mcp.Id, Tool__c = tool.Id);
        insert topicMap;
        insert topicToolMap;
        insert mcpToolMap;

        Assert.areEqual(agent.Id + '_' + topic.Id,
            [SELECT Unique_Key__c FROM ApexAgent_Topic_Map__c WHERE Id = :topicMap.Id].Unique_Key__c,
            'Topic Map key should be Agent Id + Topic Id');
        Assert.areEqual(topic.Id + '_' + tool.Id,
            [SELECT Unique_Key__c FROM ApexAgent_Topic_Tool_Map__c WHERE Id = :topicToolMap.Id].Unique_Key__c,
            'Topic Tool Map key should be Topic Id + Tool Id');
        Assert.areEqual(mcp.Id + '_' + tool.Id,
            [SELECT Unique_Key__c FROM ApexAgent_MCP_Tool_Map__c WHERE Id = :mcpToolMap.Id].Unique_Key__c,
            'MCP Tool Map key should be MCP Id + Tool Id');

        // A second mapping of an existing pair fails with a readable message on the child field.
        Database.SaveResult dupTopicMap = Database.insert(
            new ApexAgent_Topic_Map__c(Agent__c = agent.Id, Topic__c = topic.Id), false);
        String topicMapError = firstError(dupTopicMap);
        Assert.isTrue(topicMapError.contains('This Topic is already mapped to this Agent'), topicMapError);
        Assert.isTrue(topicMapError.contains(topicMap.Id), 'Error should name the existing mapping: ' + topicMapError);
        Assert.areEqual('Topic__c', dupTopicMap.getErrors()[0].getFields()[0], 'Error should sit on the Topic field');

        Assert.isTrue(firstError(Database.insert(
            new ApexAgent_Topic_Tool_Map__c(Topic__c = topic.Id, Tool__c = tool.Id), false)).contains('already mapped'),
            'Duplicate Topic Tool Map should be rejected');
        Assert.isTrue(firstError(Database.insert(
            new ApexAgent_MCP_Tool_Map__c(MCP__c = mcp.Id, Tool__c = tool.Id), false)).contains('already mapped'),
            'Duplicate MCP Tool Map should be rejected');

        // Two copies of a new pair in one batch: the first saves, the second is rejected.
        ApexAgent_Tool__c secondTool = buildTool('FakeJunctionToolTwo');
        insert secondTool;
        List<Database.SaveResult> batchResults = Database.insert(new List<ApexAgent_MCP_Tool_Map__c>{
            new ApexAgent_MCP_Tool_Map__c(MCP__c = mcp.Id, Tool__c = secondTool.Id),
            new ApexAgent_MCP_Tool_Map__c(MCP__c = mcp.Id, Tool__c = secondTool.Id)
        }, false);
        Assert.isTrue(batchResults[0].isSuccess(), 'First copy in the batch should save');
        Assert.isTrue(firstError(batchResults[1]).contains('already mapped'), 'Second copy in the batch should be rejected');

        // An update to an existing mapping must not trip over its own key, and
        // it backfills a key that is missing (records created before the field existed).
        topicMap.Active__c = false;
        topicMap.Unique_Key__c = null;
        update topicMap;
        Assert.areEqual(agent.Id + '_' + topic.Id,
            [SELECT Unique_Key__c FROM ApexAgent_Topic_Map__c WHERE Id = :topicMap.Id].Unique_Key__c,
            'Update should recompute the key');
    }

    @IsTest
    static void testBulkInsertAssignsDistinctKeys() {
        ApexAgent_Topic__c topic = new ApexAgent_Topic__c(Name = 'Bulk Topic', Topic_API_Name__c = 'bulk_topic');
        insert topic;
        List<ApexAgent_Tool__c> tools = new List<ApexAgent_Tool__c>();
        for (Integer i = 0; i < 201; i++) {
            tools.add(buildTool('FakeBulkTool' + i));
        }
        insert tools;

        List<ApexAgent_Topic_Tool_Map__c> maps = new List<ApexAgent_Topic_Tool_Map__c>();
        for (ApexAgent_Tool__c tool : tools) {
            maps.add(new ApexAgent_Topic_Tool_Map__c(Topic__c = topic.Id, Tool__c = tool.Id));
        }
        Test.startTest();
        insert maps;
        Test.stopTest();

        Set<String> keys = new Set<String>();
        for (ApexAgent_Topic_Tool_Map__c saved : [SELECT Unique_Key__c FROM ApexAgent_Topic_Tool_Map__c WHERE Topic__c = :topic.Id]) {
            keys.add(saved.Unique_Key__c);
        }
        Assert.areEqual(201, keys.size(), 'Every mapping should get its own key');
        Assert.isFalse(keys.contains(null), 'No mapping should be left without a key');
    }

    @IsTest
    static void testSetupValidationRules() {
        ApexAgent_LLM__c reasoningLlm = buildLlm(true);
        ApexAgent_LLM__c plainLlm = buildLlm(false);
        insert new List<ApexAgent_LLM__c>{ reasoningLlm, plainLlm };

        // Agent rules
        Assert.isTrue(firstError(Database.insert(new ApexAgent_Agent__c(
            Name = 'A', LLM__c = plainLlm.Id, Max_Tokens__c = 0), false)).contains('Max Tokens'),
            'Zero Max Tokens should be rejected');
        Assert.isTrue(firstError(Database.insert(new ApexAgent_Agent__c(
            Name = 'A', LLM__c = plainLlm.Id, Max_Tokens__c = 100, Primary_Color__c = 'purple'), false)).contains('hex'),
            'Non-hex Primary Color should be rejected');
        Assert.isTrue(firstError(Database.insert(new ApexAgent_Agent__c(
            Name = 'A', LLM__c = plainLlm.Id, Max_Tokens__c = 100, Reasoning_Effort__c = 'high'), false)).contains('does not support reasoning'),
            'Reasoning effort on a non-reasoning LLM should be rejected');
        List<Database.SaveResult> validAgents = Database.insert(new List<ApexAgent_Agent__c>{
            new ApexAgent_Agent__c(Name = 'A', LLM__c = plainLlm.Id, Max_Tokens__c = 100, Reasoning_Effort__c = 'disabled', Primary_Color__c = '#6147B0'),
            new ApexAgent_Agent__c(Name = 'B', LLM__c = reasoningLlm.Id, Max_Tokens__c = 100, Reasoning_Effort__c = 'high')
        }, false);
        Assert.isTrue(validAgents[0].isSuccess(), 'disabled effort and a hex color should be allowed: ' + validAgents[0].getErrors());
        Assert.isTrue(validAgents[1].isSuccess(), 'Effort on a reasoning LLM should be allowed: ' + validAgents[1].getErrors());

        // LLM rules
        ApexAgent_LLM__c negativeCost = buildLlm(false);
        negativeCost.Output_Token_Cost_M__c = -1;
        Assert.isTrue(firstError(Database.insert(negativeCost, false)).contains('cannot be negative'),
            'Negative token cost should be rejected');
        ApexAgent_LLM__c badPath = buildLlm(false);
        badPath.Chat_Completions_Path__c = 'v1/messages';
        Assert.isTrue(firstError(Database.insert(badPath, false)).contains('must start with /'),
            'A path without a leading slash should be rejected');
        ApexAgent_LLM__c blankPath = buildLlm(false);
        blankPath.Chat_Completions_Path__c = null;
        Assert.isTrue(Database.insert(blankPath, false).isSuccess(), 'A blank path should be allowed');

        // Topic, Instruction and Topic Map rules
        ApexAgent_Topic__c topic = new ApexAgent_Topic__c(Name = 'T', Topic_API_Name__c = 'validation_topic');
        insert topic;
        Assert.isFalse(Database.insert(new ApexAgent_Topic__c(Name = 'T2', Topic_API_Name__c = 'VALIDATION_TOPIC'), false).isSuccess(),
            'Topic API Name should be unique regardless of case');
        Assert.isTrue(firstError(Database.insert(new ApexAgent_Instruction__c(
            Topic__c = topic.Id, Name = 'I', Order__c = 1), false)).contains('Instruction text is required'),
            'Blank instruction should be rejected');
        Assert.isTrue(firstError(Database.insert(new ApexAgent_Instruction__c(
            Topic__c = topic.Id, Name = 'I', Order__c = -1, Instruction__c = 'Do things'), false)).contains('Order cannot be negative'),
            'Negative instruction order should be rejected');
        Assert.isTrue(firstError(Database.insert(new ApexAgent_Topic_Map__c(
            Agent__c = validAgents[0].getId(), Topic__c = topic.Id, Order__c = -1), false)).contains('Order cannot be negative'),
            'Negative topic map order should be rejected');
    }
}
