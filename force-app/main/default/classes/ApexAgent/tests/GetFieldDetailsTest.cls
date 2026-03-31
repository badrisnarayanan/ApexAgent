@IsTest
private class GetFieldDetailsTest {

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInvalidInput() {
        GetFieldDetails tool = new GetFieldDetails();

        // null input
        try {
            tool.execute(null);
            Assert.fail('Expected exception for null input');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('null'), 'Message should mention null');
        }

        // missing objectApiName
        try {
            tool.execute(new Map<String, Object>{ 'fieldApiNameList' => new List<Object>{ 'Name' } });
            Assert.fail('Expected exception for missing objectApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('objectApiName'), 'Message should mention objectApiName');
        }

        // blank objectApiName
        try {
            tool.execute(new Map<String, Object>{
                'objectApiName'    => '   ',
                'fieldApiNameList' => new List<Object>{ 'Name' }
            });
            Assert.fail('Expected exception for blank objectApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Message should mention blank');
        }

        // missing fieldApiNameList
        try {
            tool.execute(new Map<String, Object>{ 'objectApiName' => 'Account' });
            Assert.fail('Expected exception for missing fieldApiNameList');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fieldApiNameList'), 'Message should mention fieldApiNameList');
        }

        // empty list
        try {
            tool.execute(new Map<String, Object>{
                'objectApiName'    => 'Account',
                'fieldApiNameList' => new List<Object>()
            });
            Assert.fail('Expected exception for empty list');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('empty'), 'Message should mention empty');
        }

        // invalid type for fieldApiNameList
        try {
            tool.execute(new Map<String, Object>{
                'objectApiName'    => 'Account',
                'fieldApiNameList' => 42
            });
            Assert.fail('Expected exception for invalid type');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fieldApiNameList'), 'Message should mention fieldApiNameList');
        }

        // unknown object
        try {
            tool.execute(new Map<String, Object>{
                'objectApiName'    => 'NonExistentObject__xyz',
                'fieldApiNameList' => new List<Object>{ 'Name' }
            });
            Assert.fail('Expected exception for unknown object');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('NonExistentObject__xyz'),
                'Message should include the unknown object name'
            );
        }
    }

    // ─── Field not found + JSON string parsing ───────────────────────────────────

    @IsTest
    static void testFieldNotFoundAndJsonParsing() {
        GetFieldDetails tool = new GetFieldDetails();

        // field not found
        Map<String, Object> result = (Map<String, Object>) tool.execute(new Map<String, Object>{
            'objectApiName'    => 'Account',
            'fieldApiNameList' => new List<Object>{ 'NonExistentField__xyz' }
        });
        Assert.areEqual('Account', result.get('objectApiName'), 'objectApiName should be Account');
        List<Map<String, Object>> fields = (List<Map<String, Object>>) result.get('fields');
        Assert.areEqual(1, fields.size(), 'Should have one field entry');
        Assert.areEqual(false, fields[0].get('found'), 'found should be false for unknown field');
        Assert.isTrue(
            String.valueOf(fields[0].get('message')).contains('not found'),
            'Message should mention not found'
        );

        // fieldApiNameList passed as JSON string
        Map<String, Object> jsonResult = (Map<String, Object>) tool.execute(new Map<String, Object>{
            'objectApiName'    => 'Account',
            'fieldApiNameList' => '["Name"]'
        });
        List<Map<String, Object>> jsonFields = (List<Map<String, Object>>) jsonResult.get('fields');
        Assert.areEqual(1, jsonFields.size(), 'JSON string list should yield one field');
        Assert.areEqual('Name', jsonFields[0].get('name'), 'Field name should be Name');
    }

    // ─── Standard field details (STRING, REFERENCE, CURRENCY) ────────────────────

    @IsTest
    static void testStandardFieldDetails() {
        GetFieldDetails tool = new GetFieldDetails();
        Map<String, Object> result = (Map<String, Object>) tool.execute(new Map<String, Object>{
            'objectApiName'    => 'Account',
            'fieldApiNameList' => new List<Object>{ 'Name', 'OwnerId', 'AnnualRevenue' }
        });

        Assert.areEqual('Account', result.get('objectApiName'));
        List<Map<String, Object>> fields = (List<Map<String, Object>>) result.get('fields');
        Assert.areEqual(3, fields.size(), 'Should return 3 field entries');

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
        List<String> refs = (List<String>) ownerField.get('lookupReferences');
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

    // ─── Parameter schema class ──────────────────────────────────────────────────

    @IsTest
    static void testFieldListParamDefinition() {
        GetFieldDetailsFieldListParam param = new GetFieldDetailsFieldListParam();
        Map<String, Object> def = param.getDefinition();

        Assert.areEqual('array', def.get('type'), 'type should be array');
        Assert.isNotNull(def.get('description'), 'description should be present');
        Assert.isTrue(def.containsKey('items'), 'items should be present');

        Map<String, Object> items = (Map<String, Object>) def.get('items');
        Assert.areEqual('string', items.get('type'), 'items type should be string');
        Assert.isNotNull(items.get('description'), 'items description should be present');
    }

    // ─── Picklist field details ──────────────────────────────────────────────────

    @IsTest
    static void testPicklistFieldDetails() {
        GetFieldDetails tool = new GetFieldDetails();
        Map<String, Object> result = (Map<String, Object>) tool.execute(new Map<String, Object>{
            'objectApiName'    => 'Lead',
            'fieldApiNameList' => new List<Object>{ 'LeadSource', 'Status' }
        });

        List<Map<String, Object>> fields = (List<Map<String, Object>>) result.get('fields');
        Assert.areEqual(2, fields.size(), 'Should return 2 field entries');

        // LeadSource — PICKLIST
        Map<String, Object> leadSourceField = fields[0];
        Assert.areEqual('LeadSource', leadSourceField.get('name'), 'First field should be LeadSource');
        Assert.areEqual('PICKLIST', String.valueOf(leadSourceField.get('type')).toUpperCase(), 'LeadSource type should be PICKLIST');
        Assert.isTrue(leadSourceField.containsKey('picklistValues'), 'LeadSource should have picklistValues');
        List<Map<String, Object>> pv = (List<Map<String, Object>>) leadSourceField.get('picklistValues');
        Assert.isTrue(pv.size() > 0, 'LeadSource should have at least one picklist value');
        Map<String, Object> firstEntry = pv[0];
        Assert.isTrue(firstEntry.containsKey('label'), 'Picklist entry should have label');
        Assert.isTrue(firstEntry.containsKey('value'), 'Picklist entry should have value');
        Assert.isTrue(firstEntry.containsKey('isDefault'), 'Picklist entry should have isDefault');
        Assert.isFalse(leadSourceField.containsKey('lookupReferences'), 'LeadSource should not have lookupReferences');

        // Status — also PICKLIST, verify same structure
        Map<String, Object> statusField = fields[1];
        Assert.areEqual('Status', statusField.get('name'), 'Second field should be Status');
        Assert.isTrue(statusField.containsKey('picklistValues'), 'Status should have picklistValues');
    }
}
