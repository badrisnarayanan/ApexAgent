/**
 * Queries agent configuration, topics, tools, and instructions from the database
 * and builds the tool definitions array for LLM requests.
 */
public with sharing class ApexAgentTopicLoader {

    // ─────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────

    /**
     * Loads all configuration needed to run an agent by name.
     * Throws IllegalArgumentException if the agent is not found or inactive.
     */
    public static ApexAgentConfigTypes.LoadResult load(String agentName) {
        ApexAgentConfigTypes.AgentConfig config = queryAgentConfig(agentName);
        List<ApexAgentConfigTypes.TopicData> topics = new List<ApexAgentConfigTypes.TopicData>();
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>();

        // Query B1: ordered topic IDs from the junction object
        List<ApexAgent_Topic_Map__c> topicMaps = queryTopicJunction(config.agentId);
        if (!topicMaps.isEmpty()) {
            List<Id> orderedTopicIds = extractTopicIds(topicMaps);

            // Query B2: Topic__c with direct child subqueries (Instructions + Tool junction)
            Map<Id, ApexAgent_Topic__c> topicsById = queryTopics(orderedTopicIds);

            // Query C: Tool__c with parameters
            Set<Id> toolIds = collectToolIds(topicsById);
            Map<Id, ApexAgent_Tool__c> toolsById = queryTools(toolIds);

            topics = buildTopicData(orderedTopicIds, topicsById, toolsById);
            for (ApexAgent_Tool__c tool : toolsById.values()) {
                toolsByName.put(tool.Tool_API_Name__c, tool);
            }
        }

        ApexAgentConfigTypes.LoadResult result = new ApexAgentConfigTypes.LoadResult();
        result.config = config;
        result.topics = topics;
        result.toolsByName = toolsByName;
        return result;
    }

    /**
     * Builds the OpenRouter function-calling tool definitions array
     * from the tool map populated by load().
     * When showExecutionMessage is true, an execution_message parameter is injected
     * into every tool's schema so the LLM can provide a user-friendly status description.
     */
    public static List<Map<String, Object>> buildToolDefinitions(
        Map<String, ApexAgent_Tool__c> toolsByName,
        Boolean showExecutionMessage
    ) {
        List<Map<String, Object>> defs = new List<Map<String, Object>>();
        for (ApexAgent_Tool__c tool : toolsByName.values()) {
            defs.add(buildSingleToolDef(tool, showExecutionMessage == true));
        }
        return defs;
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: queries
    // ─────────────────────────────────────────────────────────────────

    private static ApexAgentConfigTypes.AgentConfig queryAgentConfig(String agentName) {
        List<ApexAgent_Agent__c> agents = [
            SELECT Id, Name, Description__c, Max_Tokens__c,
                   Conversation_Depth__c, Reasoning_Effort__c, Tool_Log_Depth__c,
                   Show_Execution_Message__c,
                   LLM__r.Named_Credential__c, LLM__r.Model_API_Name__c,
                   LLM__r.Family__c, LLM__r.Chat_Completions_Path__c,
                   LLM__r.Supports_Reasoning__c,
                   LLM__r.Uncached_Input_Token_Cost_M__c,
                   LLM__r.Cached_Input_Token_Cost_M__c,
                   LLM__r.Output_Token_Cost_M__c
            FROM ApexAgent_Agent__c
            WHERE Name = :agentName AND Active__c = true
            WITH USER_MODE
            LIMIT 1
        ];

        if (agents.isEmpty()) {
            throw new IllegalArgumentException(
                'ApexAgent not found or inactive: ' + agentName
            );
        }

        ApexAgent_Agent__c rec = agents[0];
        ApexAgentConfigTypes.AgentConfig cfg = new ApexAgentConfigTypes.AgentConfig();
        cfg.agentId               = rec.Id;
        cfg.agentName             = rec.Name;
        cfg.agentDescription      = rec.Description__c;
        cfg.maxTokens             = rec.Max_Tokens__c != null ? Integer.valueOf(rec.Max_Tokens__c) : 1000; // default to 1000 if not set
        cfg.conversationDepth     = rec.Conversation_Depth__c != null ? Integer.valueOf(rec.Conversation_Depth__c) : 15; // default to 15 if not set
        cfg.toolLogDepth          = rec.Tool_Log_Depth__c != null ? Integer.valueOf(rec.Tool_Log_Depth__c) : 5; // default to 5 if not set
        cfg.reasoningEffort       = rec.Reasoning_Effort__c;
        cfg.namedCredential       = rec.LLM__r.Named_Credential__c;
        cfg.modelApiName          = rec.LLM__r.Model_API_Name__c;
        cfg.chatCompletionsPath   = rec.LLM__r.Chat_Completions_Path__c;
        cfg.supportsReasoning     = rec.LLM__r.Supports_Reasoning__c;
        cfg.showExecutionMessage  = rec.Show_Execution_Message__c == true;
        cfg.modelFamily           = rec.LLM__r.Family__c;
        cfg.uncachedInputCostPerM = rec.LLM__r.Uncached_Input_Token_Cost_M__c;
        cfg.cachedInputCostPerM   = rec.LLM__r.Cached_Input_Token_Cost_M__c;
        cfg.outputCostPerM        = rec.LLM__r.Output_Token_Cost_M__c;
        return cfg;
    }

    /** Query B1 — ordered junction records to determine topic sequence. */
    private static List<ApexAgent_Topic_Map__c> queryTopicJunction(Id agentId) {
        return [
            SELECT Topic__c, Order__c
            FROM ApexAgent_Topic_Map__c
            WHERE Agent__c = :agentId AND Active__c = true
            WITH USER_MODE
            ORDER BY Order__c ASC NULLS LAST
        ];
    }

    private static List<Id> extractTopicIds(List<ApexAgent_Topic_Map__c> junctions) {
        List<Id> ids = new List<Id>();
        for (ApexAgent_Topic_Map__c tm : junctions) {
            ids.add(tm.Topic__c);
        }
        return ids;
    }

    /**
     * Query B2 — Topic__c records with their direct child subqueries.
     * Instructions and Topic_Tool_Maps are direct children of Topic__c,
     * so nested subqueries are valid here.
     */
    private static Map<Id, ApexAgent_Topic__c> queryTopics(List<Id> topicIds) {
        return new Map<Id, ApexAgent_Topic__c>([
            SELECT Id, Topic_API_Name__c, Name, Description__c,
                (SELECT Instruction__c, Order__c FROM Instructions__r
                 WHERE Active__c = true ORDER BY Order__c ASC NULLS LAST),
                (SELECT Tool__c FROM Topic_Tool_Maps__r WHERE Active__c = true)
            FROM ApexAgent_Topic__c
            WHERE Id IN :topicIds
            WITH USER_MODE
        ]);
    }

    private static Set<Id> collectToolIds(Map<Id, ApexAgent_Topic__c> topicsById) {
        Set<Id> ids = new Set<Id>();
        for (ApexAgent_Topic__c topic : topicsById.values()) {
            for (ApexAgent_Topic_Tool_Map__c ttm : topic.Topic_Tool_Maps__r) {
                if (ttm.Tool__c != null) {
                    ids.add(ttm.Tool__c);
                }
            }
        }
        return ids;
    }

    /** Query C — Tools with their parameter child records. */
    private static Map<Id, ApexAgent_Tool__c> queryTools(Set<Id> toolIds) {
        if (toolIds.isEmpty()) {
            return new Map<Id, ApexAgent_Tool__c>();
        }
        return new Map<Id, ApexAgent_Tool__c>([
            SELECT Id, Tool_API_Name__c, Description__c, Execution_Type__c,
                   Execution_Name__c, Modifies_Salesforce_Data__c,
                (SELECT Name, Type__c, Description__c, Required__c, Definition_Class__c
                 FROM Tool_Parameters__r)
            FROM ApexAgent_Tool__c
            WHERE Id IN :toolIds
            WITH USER_MODE
        ]);
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: data assembly
    // ─────────────────────────────────────────────────────────────────

    private static List<ApexAgentConfigTypes.TopicData> buildTopicData(
        List<Id> orderedTopicIds,
        Map<Id, ApexAgent_Topic__c> topicsById,
        Map<Id, ApexAgent_Tool__c> toolsById
    ) {
        List<ApexAgentConfigTypes.TopicData> result = new List<ApexAgentConfigTypes.TopicData>();
        for (Id topicId : orderedTopicIds) {
            ApexAgent_Topic__c topic = topicsById.get(topicId);
            if (topic == null) {
                continue;
            }

            ApexAgentConfigTypes.TopicData td = new ApexAgentConfigTypes.TopicData();
            td.topicApiName        = topic.Topic_API_Name__c;
            td.topicName           = topic.Name;
            td.topicDescription    = topic.Description__c;
            td.orderedInstructions = new List<String>();
            td.toolApiNames        = new List<String>();

            for (ApexAgent_Instruction__c instr : topic.Instructions__r) {
                if (String.isNotBlank(instr.Instruction__c)) {
                    td.orderedInstructions.add(instr.Instruction__c);
                }
            }

            for (ApexAgent_Topic_Tool_Map__c ttm : topic.Topic_Tool_Maps__r) {
                ApexAgent_Tool__c tool = toolsById.get(ttm.Tool__c);
                if (tool != null) {
                    td.toolApiNames.add(tool.Tool_API_Name__c);
                }
            }

            result.add(td);
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: tool definition builder
    // ─────────────────────────────────────────────────────────────────

    private static Map<String, Object> buildSingleToolDef(ApexAgent_Tool__c tool, Boolean showExecutionMessage) {
        Map<String, Object> properties = new Map<String, Object>();
        List<String> required = new List<String>();

        for (ApexAgent_Tool_Parameter__c param : tool.Tool_Parameters__r) {
            Map<String, Object> propDef;

            if (String.isNotBlank(param.Definition_Class__c)) {
                Type defType = Type.forName(param.Definition_Class__c);
                if (defType != null) {
                    ApexAgentParameterDefinition defInstance =
                        (ApexAgentParameterDefinition) defType.newInstance();
                    propDef = defInstance.getDefinition();
                } else {
                    propDef = new Map<String, Object>{
                        'type' => param.Type__c,
                        'description' => param.Description__c
                    };
                }
            } else {
                propDef = new Map<String, Object>{
                    'type' => param.Type__c,
                    'description' => param.Description__c
                };
            }

            properties.put(param.Name, propDef);
            if (param.Required__c) {
                required.add(param.Name);
            }
        }

        if (showExecutionMessage) {
            properties.put('execution_message', new Map<String, Object>{
                'type'        => 'string',
                'description' => 'Brief, user-friendly description of what you are doing '
                    + 'with this specific tool call, in present continuous tense '
                    + '(e.g. \'Searching for account records\'). '
                    + 'Under 60 characters. Do not end with ellipsis.'
            });
            required.add('execution_message');
        }

        Map<String, Object> parameters = new Map<String, Object>{
            'type' => 'object',
            'properties' => properties
        };
        if (!required.isEmpty()) {
            parameters.put('required', required);
        }

        return new Map<String, Object>{
            'type' => 'function',
            'function' => new Map<String, Object>{
                'name' => tool.Tool_API_Name__c,
                'description' => tool.Description__c,
                'parameters' => parameters
            }
        };
    }
}
