@IsTest
private class GetFieldDetailsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInvalidInput() {
        // blank objectApiName
        try {
            run('   ', new List<String>{ 'Name' });
            Assert.fail('Expected exception for blank objectApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        // missing/empty fieldApiNameList
        try {
            run('Account', new List<String>());
            Assert.fail('Expected exception for empty list');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fieldApiNameList'), 'Message should mention fieldApiNameList');
        }

        // blank entry within fieldApiNameList
        try {
            run('Account', new List<String>{ 'Name', '  ' });
            Assert.fail('Expected exception for blank list entry');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        // unknown object
        try {
            run('NonExistentObject__xyz', new List<String>{ 'Name' });
            Assert.fail('Expected exception for unknown object');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('NonExistentObject__xyz'),
                'Message should include the unknown object name'
            );
        }
    }

    // ─── Field not found ──────────────────────────────────────────────────────────

    @IsTest
    static void testFieldNotFound() {
        Map<String, Object> result = run('Account', new List<String>{ 'NonExistentField__xyz' });
        Assert.areEqual('Account', result.get('objectApiName'), 'objectApiName should be Account');
        List<Object> fields = (List<Object>) result.get('fields');
        Assert.areEqual(1, fields.size(), 'Should have one field entry');
        Map<String, Object> field = (Map<String, Object>) fields[0];
        Assert.areEqual(false, field.get('found'), 'found should be false for unknown field');
        Assert.isTrue(
            String.valueOf(field.get('message')).contains('not found'),
            'Message should mention not found'
        );
    }

    // ─── Standard field details (STRING, REFERENCE, CURRENCY) ────────────────────

    @IsTest
    static void testStandardFieldDetails() {
        Map<String, Object> result = run('Account', new List<String>{ 'Name', 'OwnerId', 'AnnualRevenue' });

        Assert.areEqual('Account', result.get('objectApiName'));
        List<Object> rawFields = (List<Object>) result.get('fields');
        Assert.areEqual(3, rawFields.size(), 'Should return 3 field entries');
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        for (Object f : rawFields) { fields.add((Map<String, Object>) f); }

        // Name — required, name field, STRING
        Map<String, Object> nameField = fields[0];
        Assert.areEqual('Name', nameField.get('name'), 'First field should be Name');
        Assert.areEqual('STRING', nameField.get('soapType'), 'Name soapType should be STRING');
        Assert.areEqual(true, nameField.get('isRequired'), 'Name should be required');
        Assert.areEqual(true, nameField.get('isNameField'), 'Name should be the name field');
        Assert.areEqual(true, nameField.get('isAccessible'), 'Name should be accessible');
        Assert.areEqual(true, nameField.get('isCreateable'), 'Name should be createable');
        Assert.areEqual(true, nameField.get('isUpdateable'), 'Name should be updateable');
        Assert.isNotNull(nameField.get('label'), 'label should be present');
        Assert.isNotNull(nameField.get('type'), 'type should be present');
        Assert.isNotNull(nameField.get('length'), 'length should be present');
        // Name is not a picklist or lookup — these keys should not be present
        Assert.isFalse(nameField.containsKey('picklistValues'), 'Name should not have picklistValues');
        Assert.isFalse(nameField.containsKey('lookupReferences'), 'Name should not have lookupReferences');

        // OwnerId — REFERENCE, lookup to User/Group
        Map<String, Object> ownerField = fields[1];
        Assert.areEqual('OwnerId', ownerField.get('name'), 'Second field should be OwnerId');
        Assert.isTrue(
            String.valueOf(ownerField.get('soapType')).equalsIgnoreCase('ID'),
            'OwnerId soapType should be ID'
        );
        Assert.isTrue(ownerField.containsKey('lookupReferences'), 'OwnerId should have lookupReferences');
        List<Object> refs = (List<Object>) ownerField.get('lookupReferences');
        Assert.isTrue(refs.size() >= 1, 'OwnerId should reference at least one object');

        // AnnualRevenue — CURRENCY/DOUBLE, numeric
        Map<String, Object> revenueField = fields[2];
        Assert.areEqual('AnnualRevenue', revenueField.get('name'), 'Third field should be AnnualRevenue');
        Assert.isNotNull(revenueField.get('precision'), 'precision should be present');
        Assert.isNotNull(revenueField.get('scale'), 'scale should be present');
        Assert.isFalse(revenueField.containsKey('picklistValues'), 'AnnualRevenue should not have picklistValues');

        // Verify all mandatory attributes are present on every field
        for (Map<String, Object> fd : fields) {
            Assert.isTrue(fd.containsKey('isAutoNumber'), 'isAutoNumber should be present');
            Assert.isTrue(fd.containsKey('isCalculated'), 'isCalculated should be present');
            Assert.isTrue(fd.containsKey('isEncrypted'), 'isEncrypted should be present');
            Assert.isTrue(fd.containsKey('isExternalId'), 'isExternalId should be present');
            Assert.isTrue(fd.containsKey('isFilterable'), 'isFilterable should be present');
            Assert.isTrue(fd.containsKey('isSortable'), 'isSortable should be present');
            Assert.isTrue(fd.containsKey('isGroupable'), 'isGroupable should be present');
            Assert.isTrue(fd.containsKey('isNillable'), 'isNillable should be present');
            Assert.isTrue(fd.containsKey('isDefaultedOnCreate'), 'isDefaultedOnCreate should be present');
            Assert.isTrue(fd.containsKey('isDependentPicklist'), 'isDependentPicklist should be present');
            Assert.isTrue(fd.containsKey('isRestrictedPicklist'), 'isRestrictedPicklist should be present');
            Assert.isTrue(fd.containsKey('isFormulaTreatNullNumberAsZero'), 'isFormulaTreatNullNumberAsZero should be present');
            Assert.isTrue(fd.containsKey('isCaseSensitive'), 'isCaseSensitive should be present');
        }
    }

    // ─── Picklist field details ──────────────────────────────────────────────────

    @IsTest
    static void testPicklistFieldDetails() {
        Map<String, Object> result = run('Lead', new List<String>{ 'LeadSource', 'Status' });

        List<Object> rawFields = (List<Object>) result.get('fields');
        Assert.areEqual(2, rawFields.size(), 'Should return 2 field entries');
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        for (Object f : rawFields) { fields.add((Map<String, Object>) f); }

        // LeadSource — PICKLIST
        Map<String, Object> leadSourceField = fields[0];
        Assert.areEqual('LeadSource', leadSourceField.get('name'), 'First field should be LeadSource');
        Assert.areEqual('PICKLIST', String.valueOf(leadSourceField.get('type')).toUpperCase(), 'LeadSource type should be PICKLIST');
        Assert.isTrue(leadSourceField.containsKey('picklistValues'), 'LeadSource should have picklistValues');
        List<Object> pv = (List<Object>) leadSourceField.get('picklistValues');
        Assert.isTrue(pv.size() > 0, 'LeadSource should have at least one picklist value');
        Map<String, Object> firstEntry = (Map<String, Object>) pv[0];
        Assert.isTrue(firstEntry.containsKey('label'), 'Picklist entry should have label');
        Assert.isTrue(firstEntry.containsKey('value'), 'Picklist entry should have value');
        Assert.isTrue(firstEntry.containsKey('isDefault'), 'Picklist entry should have isDefault');
        Assert.isFalse(leadSourceField.containsKey('lookupReferences'), 'LeadSource should not have lookupReferences');

        // Status — also PICKLIST, verify same structure
        Map<String, Object> statusField = fields[1];
        Assert.areEqual('Status', statusField.get('name'), 'Second field should be Status');
        Assert.isTrue(statusField.containsKey('picklistValues'), 'Status should have picklistValues');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static Map<String, Object> run(String objectApiName, List<String> fieldApiNameList) {
        GetFieldDetails.Input inp = new GetFieldDetails.Input();
        inp.objectApiName = objectApiName;
        inp.fieldApiNameList = fieldApiNameList;
        List<GetFieldDetails.Output> out = GetFieldDetails.run(new List<GetFieldDetails.Input>{ inp });
        return (Map<String, Object>) JSON.deserializeUntyped(out[0].resultJson);
    }
}
