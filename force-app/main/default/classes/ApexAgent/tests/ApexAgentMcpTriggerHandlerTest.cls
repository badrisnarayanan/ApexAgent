/**
 * Verifies Endpoint_URL__c derivation on ApexAgent_MCP__c. The expected value
 * is computed from the org's own ApexAgent_MCP_Server Site, so the assertions
 * hold whether or not that Site is active in the org running the tests (URL
 * blank when it isn't).
 */
@IsTest
private class ApexAgentMcpTriggerHandlerTest {

    private static final String ENDPOINT_PATH = '/services/apexrest/ApexAgent/mcp/';

    private static String expectedBaseUrl() {
        List<DomainSite> domainSites = [
            SELECT Domain.Domain, PathPrefix
            FROM DomainSite
            WHERE Site.Name = 'ApexAgent_MCP_Server' AND Site.Status = 'Active'
            LIMIT 1
        ];
        if (domainSites.isEmpty()) {
            return null;
        }
        String pathPrefix = domainSites[0].PathPrefix;
        return 'https://' + domainSites[0].Domain.Domain + (pathPrefix == '/' ? '' : pathPrefix);
    }

    private static String expectedUrl(String apiName) {
        String baseUrl = expectedBaseUrl();
        return baseUrl == null ? null : baseUrl + ENDPOINT_PATH + apiName;
    }

    @IsTest
    static void testEndpointUrlOnInsertRenameAndUnrelatedUpdate() {
        ApexAgent_MCP__c server = new ApexAgent_MCP__c(Name = 'URL Server', MCP_API_Name__c = 'urlserver', Active__c = true);
        insert server;

        Assert.areEqual(
            expectedUrl('urlserver'),
            [SELECT Endpoint_URL__c FROM ApexAgent_MCP__c WHERE Id = :server.Id].Endpoint_URL__c,
            'Insert should derive the URL from the MCP Site and the API name'
        );

        server.MCP_API_Name__c = 'renamedserver';
        update server;
        Assert.areEqual(
            expectedUrl('renamedserver'),
            [SELECT Endpoint_URL__c FROM ApexAgent_MCP__c WHERE Id = :server.Id].Endpoint_URL__c,
            'Changing the API name should recompute the URL'
        );

        // Updates that don't touch the API name leave the URL alone.
        server.Endpoint_URL__c = 'https://manual.example.com';
        server.Name = 'Renamed Label Only';
        update server;
        Assert.areEqual(
            'https://manual.example.com',
            [SELECT Endpoint_URL__c FROM ApexAgent_MCP__c WHERE Id = :server.Id].Endpoint_URL__c,
            'An update that does not change the API name should not recompute the URL'
        );
    }

    @IsTest
    static void testBulkInsertResolvesSiteOnce() {
        List<ApexAgent_MCP__c> servers = new List<ApexAgent_MCP__c>();
        for (Integer i = 0; i < 201; i++) {
            servers.add(new ApexAgent_MCP__c(Name = 'Bulk Server ' + i, MCP_API_Name__c = 'bulk' + i, Active__c = true));
        }

        Integer queriesBefore = Limits.getQueries();
        insert servers;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;

        // 201 records reach the trigger as two chunks (200 + 1), and each chunk
        // runs at most the Site, DomainSite and Domain queries once - never per
        // record (fewer if the org has no active MCP Site).
        Assert.isTrue(queriesUsed <= 6, 'Expected at most 3 queries for each of the 2 trigger chunks; used ' + queriesUsed);

        Map<Id, ApexAgent_MCP__c> saved = new Map<Id, ApexAgent_MCP__c>([
            SELECT MCP_API_Name__c, Endpoint_URL__c FROM ApexAgent_MCP__c WHERE Id IN :servers
        ]);
        Assert.areEqual(201, saved.size(), 'All records should have been saved');
        String baseUrl = expectedBaseUrl();
        for (ApexAgent_MCP__c record : saved.values()) {
            String expected = baseUrl == null ? null : baseUrl + ENDPOINT_PATH + record.MCP_API_Name__c;
            Assert.areEqual(expected, record.Endpoint_URL__c, 'Each record should get its own API name in the URL');
        }
    }
}
