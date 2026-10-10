@IsTest
private class ApexAgentGetOrgInfoTest {

    // ─── Happy path — direct static call ─────────────────────────────────────────

    @IsTest
    static void testReturnsOrgDetailsAndRecordUrlTemplate() {
        List<ApexAgentGetOrgInfo.Output> results = ApexAgentGetOrgInfo.run();

        Assert.areEqual(1, results.size(), 'Exactly one result expected');
        ApexAgentGetOrgInfo.Output o = results[0];
        Organization org = [SELECT Id, IsSandbox, OrganizationType, InstanceName FROM Organization LIMIT 1];
        Assert.areEqual(org.Id, o.orgId, 'orgId should be the running org');
        Assert.areEqual(UserInfo.getOrganizationName(), o.orgName, 'orgName should be the running org');
        Assert.areEqual(org.IsSandbox, o.isSandbox, 'isSandbox should match the org');
        Assert.areEqual(org.OrganizationType, o.edition, 'edition should match the org');
        Assert.areEqual(org.InstanceName, o.instanceName, 'instanceName should match the org');
        Assert.isNotNull(o.defaultTimeZone, 'defaultTimeZone should be set');
        Assert.isNotNull(o.defaultLocale, 'defaultLocale should be set');

        Assert.areEqual(URL.getOrgDomainUrl().toExternalForm(), o.myDomainUrl, 'myDomainUrl should be the org domain URL');
        Assert.areEqual('https://' + DomainCreator.getLightningHostname(), o.lightningBaseUrl, 'lightningBaseUrl should be the Lightning host');
        Assert.isTrue(o.lightningBaseUrl.startsWith('https://'), 'lightningBaseUrl should be an https URL');
        Assert.areEqual(o.myDomainUrl + '/{RecordId}', o.recordUrlTemplate, 'recordUrlTemplate should be the My Domain URL followed by the record Id');

        // The template must produce a usable record link once filled in
        String link = o.recordUrlTemplate.replace('{RecordId}', UserInfo.getUserId());
        Assert.areEqual(o.myDomainUrl + '/' + UserInfo.getUserId(), link, 'Filled template should be a record link');
    }

    // ─── Happy path — through the real Invocable.Action dispatch path ────────────

    @IsTest
    static void testHappyPathViaToolExecutor() {
        Test.startTest();
        String output = ApexAgentToolExecutor.executeInline('ApexAgentGetOrgInfo', new Map<String, Object>());
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(output);
        Assert.areEqual(String.valueOf([SELECT Id FROM Organization LIMIT 1].Id), parsed.get('orgId'), 'orgId should be the running org');
        Assert.isTrue(((String) parsed.get('recordUrlTemplate')).endsWith('/{RecordId}'),
            'recordUrlTemplate should be returned through the executor');
        Assert.isTrue(parsed.containsKey('lightningBaseUrl'), 'lightningBaseUrl should be returned');
    }
}
