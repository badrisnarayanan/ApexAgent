@IsTest
private class ApexAgentGetObjectDetailsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInvalidInput() {
        try {
            run('   ');
            Assert.fail('Expected exception for blank value');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        try {
            run('NonExistentObject__xyz');
            Assert.fail('Expected exception for unknown object');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('NonExistentObject__xyz'),
                'Message should include the unknown object name'
            );
        }
    }

    // ─── Object-level metadata ───────────────────────────────────────────────────

    @IsTest
    static void testObjectMetadata() {
        ApexAgentGetObjectDetails.Output result = run('Account');

        Assert.areEqual('Account', result.objectApiName, 'objectApiName should be Account');
        Assert.isNotNull(result.label, 'label should be present');
        Assert.areEqual(false, result.isCustom, 'Account is a standard object');
        Assert.areEqual(true, result.isAccessible, 'Account should be accessible');
        Assert.areEqual(true, result.isQueryable, 'Account should be queryable');
        Assert.areEqual(true, result.isSearchable, 'Account should be searchable');
        Assert.areEqual(true, result.isCreateable, 'Account should be createable');
        Assert.areEqual(true, result.isUpdateable, 'Account should be updateable');
        Assert.isNotNull(result.isDeleteable, 'isDeleteable should be present');
        Assert.isNotNull(result.isUndeleteable, 'isUndeleteable should be present');
        Assert.isNull(result.message, 'message should only be set when the object is not accessible');
    }

    // ─── Fields structure ────────────────────────────────────────────────────────

    @IsTest
    static void testFieldsStructure() {
        ApexAgentGetObjectDetails.Output result = run('Account');

        Assert.isTrue(!result.fields.isEmpty(), 'Fields should not be empty');
        Map<String, List<String>> entriesBySoapType = new Map<String, List<String>>();
        List<String> soapTypesInOrder = new List<String>();
        for (ApexAgentGetObjectDetails.FieldGroup fieldGroup : result.fields) {
            soapTypesInOrder.add(fieldGroup.soapType);
            Assert.isFalse(entriesBySoapType.containsKey(fieldGroup.soapType), 'Each SOAP type should appear in one group only');
            entriesBySoapType.put(fieldGroup.soapType, fieldGroup.fields);
        }

        List<String> sortedSoapTypes = soapTypesInOrder.clone();
        sortedSoapTypes.sort();
        Assert.areEqual(sortedSoapTypes, soapTypesInOrder, 'Groups should be ordered by SOAP type so the output is stable');

        // STRING type must exist (Account.Name)
        Assert.isTrue(entriesBySoapType.containsKey('STRING'), 'STRING type should be present');
        Boolean foundName = false;
        for (String entry : entriesBySoapType.get('STRING')) {
            List<String> parts = entry.split('\\|');
            Assert.isTrue(parts.size() >= 2, 'STRING field entry should have at least ApiName|Label');
            foundName = foundName || parts[0] == 'Name';
        }
        Assert.isTrue(foundName, 'Account.Name should be listed under STRING');

        // ID type must exist (OwnerId, etc.) and at least one should carry a lookup reference
        Assert.isTrue(entriesBySoapType.containsKey('ID'), 'ID type should be present for reference fields');
        Boolean foundLookup = false;
        for (String entry : entriesBySoapType.get('ID')) {
            List<String> parts = entry.split('\\|');
            Assert.isTrue(parts.size() >= 2, 'ID field entry should have at least ApiName|Label');
            if (parts.size() == 3) {
                Assert.isTrue(String.isNotBlank(parts[2]), 'Lookup reference object name should not be blank');
                foundLookup = true;
            }
        }
        Assert.isTrue(foundLookup, 'At least one reference field (e.g. OwnerId→User) should have a lookup target');
    }

    // ─── Required fields and name field ─────────────────────────────────────────

    @IsTest
    static void testRequiredAndNameField() {
        ApexAgentGetObjectDetails.Output result = run('Account');

        Assert.isNotNull(result.requiredFields, 'requiredFields should not be null');
        Assert.isTrue(result.requiredFields.contains('Name'), 'Account.Name should appear in requiredFields');
        Assert.areEqual('Name', result.nameField, 'nameField for Account should be Name');
    }

    // ─── Record types and child relationships ────────────────────────────────────

    @IsTest
    static void testRecordTypesAndChildren() {
        ApexAgentGetObjectDetails.Output result = run('Account');

        Assert.isTrue(!result.recordTypes.isEmpty(), 'Account should have at least the Master record type');
        for (String rt : result.recordTypes) {
            List<String> parts = rt.split('\\|');
            Assert.areEqual(2, parts.size(), 'Each record type entry should be Name|RecordTypeId');
            Assert.isTrue(String.isNotBlank(parts[0]), 'Record type name should not be blank');
            Assert.isTrue(String.isNotBlank(parts[1]), 'Record type Id should not be blank');
        }

        Assert.isTrue(!result.childRelationships.isEmpty(), 'Account should have child relationships');
        for (String cr : result.childRelationships) {
            List<String> parts = cr.split('\\|');
            Assert.areEqual(3, parts.size(), 'Each child relationship entry should be RelationshipName|ChildObject|Field');
            Assert.isTrue(String.isNotBlank(parts[0]), 'RelationshipName should not be blank');
            Assert.isTrue(String.isNotBlank(parts[1]), 'ChildObjectApiName should not be blank');
            Assert.isTrue(String.isNotBlank(parts[2]), 'FieldApiName should not be blank');
        }
    }

    // ─── Entry encoding ──────────────────────────────────────────────────────────

    @IsTest
    static void testEntryEncoding() {
        Assert.areEqual('Name|Account Name', ApexAgentGetObjectDetails.toEntry(new List<String>{ 'Name', 'Account Name' }));
        Assert.areEqual('A|B/C|D', ApexAgentGetObjectDetails.toEntry(new List<String>{ 'A', 'B|C', 'D' }),
            'A delimiter inside a part must be replaced so it cannot split the entry');
        Assert.areEqual('A|', ApexAgentGetObjectDetails.toEntry(new List<String>{ 'A', null }), 'A null part should become empty');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static ApexAgentGetObjectDetails.Output run(String objectApiName) {
        ApexAgentGetObjectDetails.Input inp = new ApexAgentGetObjectDetails.Input();
        inp.objectApiName = objectApiName;
        return ApexAgentGetObjectDetails.run(new List<ApexAgentGetObjectDetails.Input>{ inp })[0];
    }
}
