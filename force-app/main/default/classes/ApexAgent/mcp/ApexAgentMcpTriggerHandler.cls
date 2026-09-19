/**
 * Populates ApexAgent_MCP__c.Endpoint_URL__c on insert, or on update when
 * MCP_API_Name__c changes - since it can't be a formula field (formulas can't
 * issue SOQL or call Site.getBaseUrl()).
 *
 * Deliberately does NOT call Site.getBaseUrl() - that only returns a value
 * while the transaction is already running inside the Site's own request
 * (see ApexAgentMcpResource.getResourceUrl()). A record save from Setup/
 * Lightning UI has no active Site, so it would return null. Instead this
 * derives the same base URL via SOQL against the standard Site/DomainSite/
 * Domain objects, which works from any context - see
 * dev_docs/mcp-object-model-spec.md for the full reasoning.
 */
public with sharing class ApexAgentMcpTriggerHandler {

    private static final String MCP_SITE_NAME = 'ApexAgent_MCP_Server';

    public static void populateEndpointUrl(List<ApexAgent_MCP__c> mcpServers, Map<Id, ApexAgent_MCP__c> oldMcpServersById) {
        String baseUrl;
        Boolean baseUrlResolved = false;

        for (ApexAgent_MCP__c mcp : mcpServers) {
            ApexAgent_MCP__c oldMcp = oldMcpServersById == null ? null : oldMcpServersById.get(mcp.Id);
            Boolean isNewRecord = oldMcp == null;
            Boolean nameChanged = !isNewRecord && mcp.MCP_API_Name__c != oldMcp.MCP_API_Name__c;
            if (!isNewRecord && !nameChanged) {
                continue;
            }

            if (!baseUrlResolved) {
                baseUrl = resolveSiteBaseUrl();
                baseUrlResolved = true;
            }
            mcp.Endpoint_URL__c = baseUrl == null
                ? null
                : baseUrl + '/services/apexrest/ApexAgent/mcp/' + mcp.MCP_API_Name__c;
        }
    }

    /**
     * Queried once per trigger invocation (hoisted above the per-record loop),
     * not once per record - a save of many records still issues exactly 3
     * queries total, and an empty result (no active classic Site) is handled
     * once as null rather than throwing mid-loop.
     *
     * The Site is matched by its API name so an unrelated active classic Site
     * in the org can never be picked up by mistake.
     *
     * @return the MCP Site's base URL (e.g. https://org.my.salesforce-sites.com),
     * or null if the Site is not active or has no domain mapping.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static String resolveSiteBaseUrl() {
        List<Site> sites = [
            SELECT Id FROM Site
            WHERE Name = :MCP_SITE_NAME AND SiteType = 'Visualforce' AND Status = 'Active'
            LIMIT 1
        ];
        if (sites.isEmpty()) {
            return null;
        }

        List<DomainSite> domainSites = [
            SELECT DomainId, PathPrefix FROM DomainSite WHERE SiteId = :sites[0].Id LIMIT 1
        ];
        if (domainSites.isEmpty()) {
            return null;
        }

        List<Domain> domains = [
            SELECT Domain FROM Domain WHERE Id = :domainSites[0].DomainId LIMIT 1
        ];
        if (domains.isEmpty()) {
            return null;
        }

        String pathPrefix = domainSites[0].PathPrefix;
        return 'https://' + domains[0].Domain + (pathPrefix == '/' ? '' : pathPrefix);
    }
}
