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
        // Model Provider: the connection, and which adapter speaks to it
        public Id providerId;
        public String providerName;
        /** ApexAgent_Model_Provider__c.Provider_Type__c API value, e.g. OpenAI, Google_AI_Studio, Custom. */
        public String providerType;
        /** The adapter class when providerType is Custom. */
        public String providerApexClass;
        public String namedCredential;
        public String chatCompletionsPath;
        // LLM
        public String modelApiName;
        public Boolean supportsReasoning;
        public Boolean showExecutionMessage;
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
        /** Keyed on Apex_Class_Name__c — also the LLM-facing tool/function name. */
        public Map<String, ApexAgent_Tool__c> toolsByName;
    }
}
