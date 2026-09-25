/**
 * Unsaved ApexAgent records for tests that need real rows to act on.
 *
 * Tests insert these instead of standard objects (Account, Contact, Case):
 * the package installs into orgs whose own validation rules, triggers, flows
 * and duplicate rules on standard objects would otherwise break our tests.
 * Only Name and fields required at the field level are set, so the records
 * stay valid whatever field-level security the running user has.
 */
@IsTest
public class ApexAgentTestDataFactory {

    public static ApexAgent_LLM__c newLlm(String name) {
        return new ApexAgent_LLM__c(
            Name                = name,
            Model_API_Name__c   = 'test-model',
            Family__c           = 'Anthropic',
            Named_Credential__c = 'TestCredential'
        );
    }

    public static ApexAgent_Agent__c newAgent(String name, Id llmId) {
        return new ApexAgent_Agent__c(Name = name, LLM__c = llmId, Max_Tokens__c = 1000);
    }

    public static ApexAgent_Topic__c newTopic(String name, String topicApiName) {
        return new ApexAgent_Topic__c(Name = name, Topic_API_Name__c = topicApiName);
    }
}
