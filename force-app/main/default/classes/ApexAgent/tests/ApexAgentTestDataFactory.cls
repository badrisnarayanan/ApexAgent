/**
 * Unsaved records for tests that need real rows to act on.
 *
 * Tests insert ApexAgent records instead of standard objects (Account, Contact,
 * Case): the package installs into orgs whose own validation rules, triggers,
 * flows and duplicate rules on standard objects would otherwise break our tests.
 * Only Name and fields required at the field level are set, so the records
 * stay valid whatever field-level security the running user has.
 *
 * A few tests can't avoid a User (System.runAs needs one). They save it through
 * tryInsert and skip the part that needs it when the org's own customizations
 * reject the record, so an installer's rules never fail our tests.
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

    /** A user on the running user's profile. Save it with tryInsert. */
    public static User newUser(String lastName) {
        String suffix = uniqueSuffix();
        return new User(
            FirstName         = 'ApexAgent',
            LastName          = lastName,
            Alias             = lastName.left(4) + suffix.right(4),
            Email             = lastName.toLowerCase() + '@apexagent.test',
            Username          = lastName.toLowerCase() + suffix + '@apexagent.test',
            ProfileId         = UserInfo.getProfileId(),
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey  = 'UTF-8'
        );
    }

    /**
     * The Minimum Access profile, or null when the org doesn't expose it under
     * that name (standard profile names are translated in non-English orgs).
     */
    public static Id minimumAccessProfileId() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        return profiles.isEmpty() ? null : profiles[0].Id;
    }

    /** False when the org's own validation rules, triggers or flows reject the record. */
    public static Boolean tryInsert(SObject record) {
        try {
            insert record;
            return true;
        } catch (DmlException e) {
            return skipped('insert ' + record.getSObjectType(), e);
        }
    }

    /** False when the org won't let the records go, e.g. a permission set used in a group. */
    public static Boolean tryDelete(List<SObject> records) {
        try {
            delete records;
            return true;
        } catch (DmlException e) {
            return skipped('delete ' + records.getSObjectType(), e);
        }
    }

    public static String uniqueSuffix() {
        return String.valueOf(Crypto.getRandomInteger()).remove('-');
    }

    private static Boolean skipped(String operation, DmlException e) {
        System.debug(LoggingLevel.WARN, 'ApexAgent test skipped: this org rejected ' + operation + ' — ' + e.getMessage());
        return false;
    }
}
