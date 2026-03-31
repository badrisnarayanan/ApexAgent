@IsTest
private class UpsertRecordsTest {

    // ─── Helpers ─────────────────────────────────────────────────────────────────

    private static Map<String, Object> makeFieldEntry(String fieldApiName, Object value, String apexType) {
        return new Map<String, Object>{
            'fieldApiName' => fieldApiName,
            'value'        => value,
            'apexType'     => apexType
        };
    }

    private static Map<String, Object> makeRecord(List<Map<String, Object>> fields) {
        return new Map<String, Object>{ 'fields' => fields };
    }

    private static Map<String, Object> buildInput(
        String objectApiName,
        Boolean allOrNone,
        String externalIdFieldName,
        List<Map<String, Object>> records
    ) {
        Map<String, Object> input = new Map<String, Object>{
            'objectApiName' => objectApiName,
            'allOrNone'     => allOrNone,
            'records'       => records
        };
        if (externalIdFieldName != null) {
            input.put('externalIdFieldName', externalIdFieldName);
        }
        return input;
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        UpsertRecords tool = new UpsertRecords();

        // null input
        try {
            tool.execute(null);
            Assert.fail('Expected exception for null input');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('null'), 'Should mention null');
        }

        // missing objectApiName
        try {
            tool.execute(new Map<String, Object>{ 'allOrNone' => true, 'records' => new List<Object>() });
            Assert.fail('Expected exception for missing objectApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('objectApiName'), 'Should mention objectApiName');
        }

        // blank objectApiName
        try {
            tool.execute(new Map<String, Object>{
                'objectApiName' => '  ', 'allOrNone' => true, 'records' => new List<Object>()
            });
            Assert.fail('Expected exception for blank objectApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Should mention blank');
        }

        // missing allOrNone
        try {
            tool.execute(new Map<String, Object>{
                'objectApiName' => 'Account', 'records' => new List<Object>()
            });
            Assert.fail('Expected exception for missing allOrNone');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('allOrNone'), 'Should mention allOrNone');
        }

        // missing records
        try {
            tool.execute(new Map<String, Object>{
                'objectApiName' => 'Account', 'allOrNone' => true
            });
            Assert.fail('Expected exception for missing records');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('records'), 'Should mention records');
        }

        // empty records list
        try {
            tool.execute(buildInput('Account', true, null, new List<Map<String, Object>>()));
            Assert.fail('Expected exception for empty records');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('empty'), 'Should mention empty');
        }

        // records exceed 200
        List<Map<String, Object>> bigList = new List<Map<String, Object>>();
        for (Integer i = 0; i < 201; i++) {
            bigList.add(makeRecord(new List<Map<String, Object>>{
                makeFieldEntry('Name', 'Test', 'String')
            }));
        }
        try {
            tool.execute(buildInput('Account', true, null, bigList));
            Assert.fail('Expected exception for records > 200');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('200'), 'Should mention 200 limit');
        }

        // unknown objectApiName
        try {
            tool.execute(buildInput('NonExistentObject__xyz', true, null,
                new List<Map<String, Object>>{ makeRecord(new List<Map<String, Object>>{
                    makeFieldEntry('Name', 'x', 'String')
                }) }
            ));
            Assert.fail('Expected exception for unknown object');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('NonExistentObject__xyz'), 'Should mention object name');
        }

        // record with missing fields array
        try {
            tool.execute(buildInput('Account', true, null,
                new List<Map<String, Object>>{ new Map<String, Object>() }
            ));
            Assert.fail('Expected exception for missing fields');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fields'), 'Should mention fields');
        }

        // record with empty fields array
        try {
            tool.execute(buildInput('Account', true, null,
                new List<Map<String, Object>>{ makeRecord(new List<Map<String, Object>>()) }
            ));
            Assert.fail('Expected exception for empty fields');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('empty'), 'Should mention empty');
        }

        // missing fieldApiName
        try {
            tool.execute(buildInput('Account', true, null,
                new List<Map<String, Object>>{ makeRecord(new List<Map<String, Object>>{
                    new Map<String, Object>{ 'value' => 'x', 'apexType' => 'String' }
                }) }
            ));
            Assert.fail('Expected exception for missing fieldApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fieldApiName'), 'Should mention fieldApiName');
        }

        // missing apexType
        try {
            tool.execute(buildInput('Account', true, null,
                new List<Map<String, Object>>{ makeRecord(new List<Map<String, Object>>{
                    new Map<String, Object>{ 'fieldApiName' => 'Name', 'value' => 'x' }
                }) }
            ));
            Assert.fail('Expected exception for missing apexType');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('apexType'), 'Should mention apexType');
        }

        // invalid externalIdFieldName — non-existent field
        Account acc = new Account(Name = 'ExtId Test');
        insert acc;
        try {
            tool.execute(buildInput('Account', true, 'NonExistentField__xyz',
                new List<Map<String, Object>>{ makeRecord(new List<Map<String, Object>>{
                    makeFieldEntry('Name', 'Test', 'String')
                }) }
            ));
            Assert.fail('Expected exception for non-existent external ID field');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().contains('NonExistentField__xyz'),
                'Should mention the bad field name'
            );
        }

        // invalid externalIdFieldName — non-external-ID standard field
        try {
            tool.execute(buildInput('Account', true, 'Name',
                new List<Map<String, Object>>{ makeRecord(new List<Map<String, Object>>{
                    makeFieldEntry('Name', 'Test', 'String')
                }) }
            ));
            Assert.fail('Expected exception for non-external-ID field');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('not') || e.getMessage().containsIgnoreCase('External'),
                'Should explain the field is not an external ID'
            );
        }
    }

    // ─── convertValue — all types ────────────────────────────────────────────────

    @IsTest
    static void testConvertValue() {
        UpsertRecords tool = new UpsertRecords();

        // null value always returns null regardless of type
        Assert.isNull(tool.convertValue(null, 'String',   'f', 0), 'null → null for String');
        Assert.isNull(tool.convertValue(null, 'Boolean',  'f', 0), 'null → null for Boolean');
        Assert.isNull(tool.convertValue(null, 'Integer',  'f', 0), 'null → null for Integer');
        Assert.isNull(tool.convertValue(null, 'Date',     'f', 0), 'null → null for Date');

        // String
        Assert.areEqual('hello', tool.convertValue('hello', 'String', 'f', 0));
        Assert.areEqual('42',    tool.convertValue(42,      'String', 'f', 0));

        // ID — from string
        Account acc = new Account(Name = 'ID Test');
        insert acc;
        String accIdStr = String.valueOf(acc.Id);
        Object convertedId = tool.convertValue(accIdStr, 'ID', 'f', 0);
        Assert.areEqual(acc.Id, (Id) convertedId, 'ID from string should match');

        // ID — invalid string throws
        try {
            tool.convertValue('not-a-real-id', 'ID', 'f', 0);
            Assert.fail('Expected exception for invalid ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('not a valid Salesforce ID'), 'Should mention invalid ID');
        }

        // Boolean — already boolean
        Assert.areEqual(true,  tool.convertValue(true,    'Boolean', 'f', 0));
        Assert.areEqual(false, tool.convertValue(false,   'Boolean', 'f', 0));
        // Boolean — from string
        Assert.areEqual(true,  tool.convertValue('true',  'Boolean', 'f', 0));
        Assert.areEqual(false, tool.convertValue('false', 'Boolean', 'f', 0));
        // Boolean — invalid throws
        try {
            tool.convertValue('yes', 'Boolean', 'f', 0);
            Assert.fail('Expected exception for invalid boolean string');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('boolean'), 'Should mention boolean');
        }

        // Integer
        Assert.areEqual(5,   (Integer) tool.convertValue(5,       'Integer', 'f', 0));
        Assert.areEqual(7,   (Integer) tool.convertValue(7.9,     'Integer', 'f', 0)); // truncates
        Assert.areEqual(42,  (Integer) tool.convertValue('42',    'Integer', 'f', 0));
        try {
            tool.convertValue('abc', 'Integer', 'f', 0);
            Assert.fail('Expected exception for invalid integer');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('integer'), 'Should mention Integer');
        }

        // Decimal
        Assert.areEqual(3.14, (Decimal) tool.convertValue(3.14,  'Decimal', 'f', 0));
        Assert.areEqual(10,   (Decimal) tool.convertValue(10,    'Decimal', 'f', 0));
        Assert.areEqual(1.5,  (Decimal) tool.convertValue('1.5', 'Decimal', 'f', 0));
        try {
            tool.convertValue('xyz', 'Decimal', 'f', 0);
            Assert.fail('Expected exception for invalid decimal');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('decimal'), 'Should mention Decimal');
        }

        // Long
        Assert.areEqual(9999999999L, (Long) tool.convertValue(9999999999L,  'Long', 'f', 0));
        Assert.areEqual(5L,          (Long) tool.convertValue(5,            'Long', 'f', 0));
        Assert.areEqual(100L,        (Long) tool.convertValue('100',        'Long', 'f', 0));
        try {
            tool.convertValue('nope', 'Long', 'f', 0);
            Assert.fail('Expected exception for invalid long');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('long'), 'Should mention Long');
        }

        // Date — ISO YYYY-MM-DD
        Date isoDate = (Date) tool.convertValue('2024-06-15', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), isoDate, 'ISO date should parse');
        // Date — MM/DD/YYYY
        Date slashDate = (Date) tool.convertValue('06/15/2024', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), slashDate, 'MM/DD/YYYY should parse');
        // Date — DD-MM-YYYY
        Date euDate = (Date) tool.convertValue('15-06-2024', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), euDate, 'DD-MM-YYYY should parse');
        // Date — already a Date instance
        Date d = Date.newInstance(2024, 1, 1);
        Assert.areEqual(d, (Date) tool.convertValue(d, 'Date', 'f', 0), 'Date instance passthrough');
        // Date — invalid throws
        try {
            tool.convertValue('not-a-date', 'Date', 'f', 0);
            Assert.fail('Expected exception for invalid date');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('date'), 'Should mention date');
        }

        // Datetime — ISO 8601 with Z
        Datetime dt = (Datetime) tool.convertValue('2024-06-15T13:30:45Z', 'DateTime', 'f', 0);
        Assert.areEqual(2024, dt.year(),   'Year should be 2024');
        Assert.areEqual(6,    dt.month(),  'Month should be 6');
        Assert.areEqual(15,   dt.day(),    'Day should be 15');
        Assert.areEqual(13,   dt.hour(),   'Hour should be 13');
        Assert.areEqual(30,   dt.minute(), 'Minute should be 30');
        // Datetime — with milliseconds
        Datetime dtMs = (Datetime) tool.convertValue('2024-06-15T13:30:45.000Z', 'DateTime', 'f', 0);
        Assert.areEqual(2024, dtMs.year(), 'Year should be 2024 (with ms)');
        // Datetime — invalid throws
        try {
            tool.convertValue('not-a-datetime', 'DateTime', 'f', 0);
            Assert.fail('Expected exception for invalid datetime');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('datetime'), 'Should mention Datetime');
        }

        // Time — HH:mm:ss
        Time t = (Time) tool.convertValue('13:30:45', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(13, 30, 45, 0), t, 'Time should parse HH:mm:ss');
        // Time — with trailing Z and milliseconds
        Time tZ = (Time) tool.convertValue('09:05:00.000Z', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(9, 5, 0, 0), tZ, 'Time should strip Z and ms');
        // Time — HH:mm (no seconds)
        Time tShort = (Time) tool.convertValue('08:00', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(8, 0, 0, 0), tShort, 'Time should handle HH:mm');
        // Time — invalid throws
        try {
            tool.convertValue('not-a-time', 'Time', 'f', 0);
            Assert.fail('Expected exception for invalid time');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('time'), 'Should mention Time');
        }

        // Unsupported type throws
        try {
            tool.convertValue('x', 'Blob', 'f', 0);
            Assert.fail('Expected exception for unsupported type');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Blob'), 'Should mention the unsupported type');
        }
    }

    // ─── Insert and update via upsert ────────────────────────────────────────────

    @IsTest
    static void testInsertAndUpdate() {
        UpsertRecords tool = new UpsertRecords();

        // ── Insert: two new Account records (no Id → creates) ──────────────────
        List<Map<String, Object>> insertRecords = new List<Map<String, Object>>{
            makeRecord(new List<Map<String, Object>>{
                makeFieldEntry('Name', 'UpsertTest Alpha', 'String')
            }),
            makeRecord(new List<Map<String, Object>>{
                makeFieldEntry('Name', 'UpsertTest Beta',  'String')
            })
        };

        List<Object> insertResult = (List<Object>) tool.execute(
            buildInput('Account', true, null, insertRecords)
        );

        Assert.areEqual(2, insertResult.size(), 'Result should have 2 entries');

        Map<String, Object> r0 = (Map<String, Object>) insertResult[0];
        Map<String, Object> r1 = (Map<String, Object>) insertResult[1];
        Assert.areEqual(true, r0.get('success'), 'First record should succeed');
        Assert.areEqual(true, r1.get('success'), 'Second record should succeed');
        Assert.areEqual(true, r0.get('created'), 'First record should be created');
        Assert.areEqual(true, r1.get('created'), 'Second record should be created');
        String id0 = (String) r0.get('id');
        String id1 = (String) r1.get('id');
        Assert.isNotNull(id0, 'First result should have an id');
        Assert.isNotNull(id1, 'Second result should have an id');

        // ── Update: re-upsert the same records by Id ───────────────────────────
        List<Map<String, Object>> updateRecords = new List<Map<String, Object>>{
            makeRecord(new List<Map<String, Object>>{
                makeFieldEntry('Id',   id0,                    'ID'),
                makeFieldEntry('Name', 'UpsertTest Alpha v2',  'String')
            }),
            makeRecord(new List<Map<String, Object>>{
                makeFieldEntry('Id',   id1,                    'ID'),
                makeFieldEntry('Name', 'UpsertTest Beta v2',   'String')
            })
        };

        List<Object> updateResult = (List<Object>) tool.execute(
            buildInput('Account', true, null, updateRecords)
        );

        Assert.areEqual(false, ((Map<String, Object>) updateResult[0]).get('created'),
            'Record 0 should be updated, not created');
        Assert.areEqual(false, ((Map<String, Object>) updateResult[1]).get('created'),
            'Record 1 should be updated, not created');

        // Verify Name was actually updated in the database
        List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :new List<Id>{
            Id.valueOf(id0), Id.valueOf(id1)
        } ORDER BY Name];
        Assert.areEqual('UpsertTest Alpha v2', accounts[0].Name, 'Name should be updated for Alpha');
        Assert.areEqual('UpsertTest Beta v2',  accounts[1].Name, 'Name should be updated for Beta');
    }

    // ─── DML error handling and parameter definition ──────────────────────────────

    @IsTest
    static void testDmlErrorAndParamDefinition() {
        UpsertRecords tool = new UpsertRecords();

        // ── allOrNone=false: one valid record + one record setting a required
        //    field to blank — partial success should be returned ────────────────
        List<Map<String, Object>> partialRecords = new List<Map<String, Object>>{
            makeRecord(new List<Map<String, Object>>{
                makeFieldEntry('Name', 'UpsertTest Partial OK', 'String')
            }),
            makeRecord(new List<Map<String, Object>>{
                makeFieldEntry('Name', null, 'String') // Account.Name is required — will fail
            })
        };

        List<Object> partialResult = (List<Object>) tool.execute(
            buildInput('Account', false, null, partialRecords)
        );

        Assert.areEqual(2, partialResult.size(), 'Should have 2 result entries');

        Integer successCt = 0;
        Integer failCount = 0;
        Boolean foundErrors = false;
        for (Object entry : partialResult) {
            Map<String, Object> det = (Map<String, Object>) entry;
            if (det.get('success') == true) {
                successCt++;
            } else {
                failCount++;
                List<Object> errs = (List<Object>) det.get('errors');
                Assert.isFalse(errs.isEmpty(), 'Errors list should not be empty');
                Map<String, Object> err0 = (Map<String, Object>) errs[0];
                Assert.isNotNull(err0.get('message'),    'Error should have message');
                Assert.isNotNull(err0.get('statusCode'), 'Error should have statusCode');
                foundErrors = true;
            }
        }
        Assert.isTrue(successCt >= 1, 'At least one record should succeed');
        Assert.isTrue(failCount  >= 1, 'At least one record should fail');
        Assert.isTrue(foundErrors,     'At least one result entry should have errors');

        // ── UpsertRecordsRecordsParam definition shape ────────────────────────
        UpsertRecordsRecordsParam paramDef = new UpsertRecordsRecordsParam();
        Map<String, Object> def = paramDef.getDefinition();

        Assert.areEqual('array', def.get('type'), 'Top-level type should be array');
        Assert.isNotNull(def.get('items'), 'Should have items');

        Map<String, Object> items = (Map<String, Object>) def.get('items');
        Assert.areEqual('object', items.get('type'), 'Item type should be object');
        Assert.areEqual(false,    items.get('additionalProperties'), 'additionalProperties should be false');

        Map<String, Object> itemProps = (Map<String, Object>) items.get('properties');
        Assert.isTrue(itemProps.containsKey('fields'), 'items.properties should have fields');

        Map<String, Object> fieldsDef = (Map<String, Object>) itemProps.get('fields');
        Assert.areEqual('array', fieldsDef.get('type'), 'fields should be array');

        Map<String, Object> fieldItemDef = (Map<String, Object>) fieldsDef.get('items');
        Assert.areEqual('object', fieldItemDef.get('type'), 'field item type should be object');
        Assert.areEqual(false,    fieldItemDef.get('additionalProperties'), 'field item additionalProperties should be false');

        Map<String, Object> fieldItemProps = (Map<String, Object>) fieldItemDef.get('properties');
        Assert.isTrue(fieldItemProps.containsKey('fieldApiName'), 'Should have fieldApiName');
        Assert.isTrue(fieldItemProps.containsKey('value'),        'Should have value');
        Assert.isTrue(fieldItemProps.containsKey('apexType'),     'Should have apexType');

        Map<String, Object> apexTypeDef = (Map<String, Object>) fieldItemProps.get('apexType');
        List<Object> enumVals = (List<Object>) apexTypeDef.get('enum');
        Assert.isTrue(enumVals.size() == 9, 'apexType enum should have 9 values');
    }
}
