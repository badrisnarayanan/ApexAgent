@IsTest
private class GetObjectDetailsTest {

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
        Map<String, Object> result = run('Account');

        Assert.areEqual('Account', result.get('objectAPIName'), 'objectAPIName should be Account');
        Assert.isNotNull(result.get('label'), 'label should be present');
        Assert.areEqual(false, result.get('isCustom'), 'Account is a standard object');
        Assert.areEqual(true, result.get('isAccessible'), 'Account should be accessible');
        Assert.areEqual(true, result.get('isQueryable'), 'Account should be queryable');
        Assert.areEqual(true, result.get('isSearchable'), 'Account should be searchable');
        Assert.areEqual(true, result.get('isCreateable'), 'Account should be createable');
        Assert.areEqual(true, result.get('isUpdateable'), 'Account should be updateable');
        Assert.isNotNull(result.get('isDeleteable'), 'isDeleteable should be present');
        Assert.isNotNull(result.get('isUndeleteable'), 'isUndeleteable should be present');
    }

    // ─── Fields structure ────────────────────────────────────────────────────────

    @IsTest
    static void testFieldsStructure() {
        Map<String, Object> result = run('Account');

        Assert.isTrue(result.containsKey('fields'), 'Result should contain fields');
        Assert.isTrue(result.containsKey('fieldsFormat'), 'Result should contain fieldsFormat');
        Assert.isNotNull(result.get('fieldsFormat'), 'fieldsFormat should not be null');

        Map<String, Object> fields = (Map<String, Object>) result.get('fields');
        Assert.isTrue(!fields.isEmpty(), 'Fields map should not be empty');

        // STRING type must exist (Account.Name)
        Assert.isTrue(fields.containsKey('STRING'), 'STRING type should be present');
        for (Object rawEntry : (List<Object>) fields.get('STRING')) {
            List<Object> entry = (List<Object>) rawEntry;
            Assert.isTrue(entry.size() >= 2, 'STRING field entry should have at least [Name, Label]');
        }

        // ID type must exist (OwnerId, etc.) and at least one should carry a lookup reference
        Assert.isTrue(fields.containsKey('ID'), 'ID type should be present for reference fields');
        Boolean foundLookup = false;
        for (Object rawEntry : (List<Object>) fields.get('ID')) {
            List<Object> entry = (List<Object>) rawEntry;
            Assert.isTrue(entry.size() >= 2, 'ID field entry should have at least [Name, Label]');
            if (entry.size() == 3) {
                Assert.isNotNull(entry[2], 'Lookup reference object name should not be null');
                foundLookup = true;
            }
        }
        Assert.isTrue(foundLookup, 'At least one reference field (e.g. OwnerId→User) should have a lookup target');
    }

    // ─── Required fields and name field ─────────────────────────────────────────

    @IsTest
    static void testRequiredAndNameField() {
        Map<String, Object> result = run('Account');

        Assert.isTrue(result.containsKey('requiredFields'), 'Result should contain requiredFields');
        List<Object> required = (List<Object>) result.get('requiredFields');
        Assert.isNotNull(required, 'requiredFields should not be null');
        Assert.isTrue(required.contains('Name'), 'Account.Name should appear in requiredFields');

        Assert.isTrue(result.containsKey('nameField'), 'Result should contain nameField');
        Assert.areEqual('Name', result.get('nameField'), 'nameField for Account should be Name');
    }

    // ─── Record types and child relationships ────────────────────────────────────

    @IsTest
    static void testRecordTypesAndChildren() {
        Map<String, Object> result = run('Account');

        Assert.isTrue(result.containsKey('recordTypes'), 'Result should contain recordTypes');
        Assert.isTrue(result.containsKey('recordTypesFormat'), 'Result should contain recordTypesFormat');
        List<Object> recordTypes = (List<Object>) result.get('recordTypes');
        Assert.isNotNull(recordTypes, 'recordTypes should not be null');
        Assert.isTrue(!recordTypes.isEmpty(), 'Account should have at least the Master record type');
        for (Object rawRt : recordTypes) {
            List<Object> rt = (List<Object>) rawRt;
            Assert.areEqual(2, rt.size(), 'Each record type entry should be [Name, RecordTypeId]');
            Assert.isNotNull(rt[0], 'Record type name should not be null');
            Assert.isNotNull(rt[1], 'Record type Id should not be null');
        }

        Assert.isTrue(result.containsKey('childRelationships'), 'Result should contain childRelationships');
        Assert.isTrue(result.containsKey('childRelationshipsFormat'), 'Result should contain childRelationshipsFormat');
        List<Object> childRels = (List<Object>) result.get('childRelationships');
        Assert.isNotNull(childRels, 'childRelationships should not be null');
        Assert.isTrue(!childRels.isEmpty(), 'Account should have child relationships');
        for (Object rawCr : childRels) {
            List<Object> cr = (List<Object>) rawCr;
            Assert.areEqual(3, cr.size(), 'Each child relationship entry should be [RelationshipName, ChildObject, Field]');
            Assert.isNotNull(cr[0], 'RelationshipName should not be null');
            Assert.isNotNull(cr[1], 'ChildObjectApiName should not be null');
            Assert.isNotNull(cr[2], 'FieldApiName should not be null');
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static Map<String, Object> run(String objectApiName) {
        GetObjectDetails.Input inp = new GetObjectDetails.Input();
        inp.objectApiName = objectApiName;
        List<GetObjectDetails.Output> out = GetObjectDetails.run(new List<GetObjectDetails.Input>{ inp });
        return (Map<String, Object>) JSON.deserializeUntyped(out[0].resultJson);
    }
}
