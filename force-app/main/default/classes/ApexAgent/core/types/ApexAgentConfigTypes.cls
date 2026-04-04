/**
 * Configuration and data-holder types for the ApexAgent orchestration layer.
 */
public with sharing class ApexAgentConfigTypes {

    /** Flat config struct populated from Agent__c + LLM__c query. */
    public class AgentConfig {
        public Id agentId;
        public String agentName;
        public String agentDescription;
        public Integer maxTokens;
        public Integer conversationDepth;
        public Integer toolLogDepth;
        /** Values: low / medium / high / xhigh / minimal / none / disabled */
        public String reasoningEffort;
        public String modelFamily; // Anthropic / OpenAI / Google
        // LLM callout fields
        public String namedCredential;
        public String modelApiName;
        public String chatCompletionsPath;
        public Boolean supportsReasoning;
        // Cost per million tokens
        public Decimal uncachedInputCostPerM;
        public Decimal cachedInputCostPerM;
        public Decimal outputCostPerM;
    }

    /** One topic with its ordered instructions and assigned tool names. */
    public class TopicData {
        public String topicApiName;
        public String topicName;
        public String topicDescription;
        public List<String> orderedInstructions;
        public List<String> toolApiNames;
    }

    /** Result returned by ApexAgentTopicLoader.load(). */
    public class LoadResult {
        public AgentConfig config;
        public List<TopicData> topics;
        /** Keyed on Tool_API_Name__c; values include Tool_Parameters__r sub-records. */
        public Map<String, ApexAgent_Tool__c> toolsByName;
    }
}
