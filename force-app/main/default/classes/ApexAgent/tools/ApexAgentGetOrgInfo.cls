/**
 * Apex Action tool: returns details of the Salesforce org the tool runs in,
 * including the base URLs needed to turn record Ids into clickable links.
 *
 * An MCP client only sees bare record Ids, so without this it shows the user
 * Ids they cannot open. The record URL template lets it link every record instead.
 */
public with sharing class ApexAgentGetOrgInfo {

    private static final String RECORD_PATH_TEMPLATE = '/{RecordId}';

    public class Output {
        @InvocableVariable(label='Org Name' description='Name of the Salesforce org (company).')
        public String orgName;

        @InvocableVariable(label='Org Id' description='18-character Id of the Salesforce org.')
        public Id orgId;

        @InvocableVariable(label='Edition' description='Salesforce edition of the org (e.g. "Enterprise Edition", "Developer Edition").')
        public String edition;

        @InvocableVariable(label='Is Sandbox' description='True when the org is a sandbox, false for production or developer orgs.')
        public Boolean isSandbox;

        @InvocableVariable(label='Instance Name' description='Salesforce instance the org runs on (e.g. "USA123").')
        public String instanceName;

        @InvocableVariable(label='Default Time Zone' description='Default time zone of the org (e.g. "America/New_York").')
        public String defaultTimeZone;

        @InvocableVariable(label='Default Locale' description='Default locale of the org (e.g. "en_US").')
        public String defaultLocale;

        @InvocableVariable(label='My Domain URL' description='The org\'s My Domain URL (e.g. "https://acme.my.salesforce.com").')
        public String myDomainUrl;

        @InvocableVariable(label='Lightning Base URL' description='Base URL of the org\'s Lightning Experience (e.g. "https://acme.lightning.force.com").')
        public String lightningBaseUrl;

        @InvocableVariable(label='Record URL Template' description='Template for a link that opens a record. Replace {RecordId} with the record Id (e.g. "https://acme.my.salesforce.com/001XXXXXXXXXXXXXXX"). Works for every object, standard or custom, so the object API name is not needed.')
        public String recordUrlTemplate;
    }

    @InvocableMethod(label='Get Org Info' description='Returns details of the Salesforce org: name, Id, edition, sandbox flag, instance, default time zone and locale, the My Domain URL, the Lightning base URL, and a template for building record links.\n\nWhen to use:\n\nAt the start of a conversation, before you mention any Salesforce record to the user. Call it once and reuse the result.\nWhenever you return or mention a record, never show a bare record Id. Show a clickable link built from recordUrlTemplate by replacing {RecordId} with the record Id, e.g. https://acme.my.salesforce.com/001XXXXXXXXXXXXXXX. It works for every object, so you do not need the object API name. Use the record\'s Name (or another readable field) as the link text.\nYou need to know which org you are connected to, or whether it is a sandbox.\n\nWhen not to use:\n\nYou already called it in this conversation; the result does not change.\nYou need details of the user rather than the org; use ApexAgentGetCurrentUser.')
    public static List<Output> run() {
        try {
            return new List<Output>{ buildOutput(queryOrganization()) };
        } catch (Exception e) {
            ApexAgentToolErrorContext.record(e);
            throw e;
        }
    }

    // The Organization row holds no record data, only org settings every user may
    // know; system mode keeps the tool working for users without View Setup.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static Organization queryOrganization() {
        return [
            SELECT Id, Name, OrganizationType, IsSandbox, InstanceName, TimeZoneSidKey, DefaultLocaleSidKey
            FROM Organization
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    private static Output buildOutput(Organization org) {
        Output o = new Output();
        o.orgName           = org.Name;
        o.orgId             = org.Id;
        o.edition           = org.OrganizationType;
        o.isSandbox         = org.IsSandbox;
        o.instanceName      = org.InstanceName;
        o.defaultTimeZone   = org.TimeZoneSidKey;
        o.defaultLocale     = org.DefaultLocaleSidKey;
        o.myDomainUrl       = URL.getOrgDomainUrl().toExternalForm();
        o.lightningBaseUrl  = 'https://' + DomainCreator.getLightningHostname();
        o.recordUrlTemplate = o.myDomainUrl + RECORD_PATH_TEMPLATE;
        return o;
    }
}
