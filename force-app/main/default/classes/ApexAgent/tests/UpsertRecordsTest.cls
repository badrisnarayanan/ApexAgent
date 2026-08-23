@IsTest
private class UpsertRecordsTest {

    // ─── Helpers ─────────────────────────────────────────────────────────────────

    private static UpsertRecords.FieldEntry fieldEntry(String fieldApiName, String value, String apexType) {
        UpsertRecords.FieldEntry fe = new UpsertRecords.FieldEntry();
        fe.fieldApiName = fieldApiName;
        fe.value = value;
        fe.apexType = apexType;
        return fe;
    }

    private static UpsertRecords.RecordInput makeRecord(List<UpsertRecords.FieldEntry> fields) {
        UpsertRecords.RecordInput ri = new UpsertRecords.RecordInput();
        ri.fields = fields;
        return ri;
    }

    private static UpsertRecords.Input buildInput(
        String objectApiName,
        Boolean allOrNone,
        String externalIdFieldName,
        List<UpsertRecords.RecordInput> records
    ) {
        UpsertRecords.Input inp = new UpsertRecords.Input();
        inp.objectApiName = objectApiName;
        inp.allOrNone = allOrNone;
        inp.externalIdFieldName = externalIdFieldName;
        inp.records = records;
        return inp;
    }

    private static Object run(UpsertRecords.Input inp) {
        List<UpsertRecords.Output> out = UpsertRecords.run(new List<UpsertRecords.Input>{ inp });
        return JSON.deserializeUntyped(out[0].resultJson);
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        // missing/blank objectApiName
        try {
            run(buildInput(null, true, null, new List<UpsertRecords.RecordInput>{
                makeRecord(new List<UpsertRecords.FieldEntry>{ fieldEntry('Name', 'x', 'String') })
            }));
            Assert.fail('Expected exception for missing objectApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('objectApiName'), 'Should mention objectApiName');
        }

        // missing allOrNone
        try {
            run(buildInput('Account', null, null, new List<UpsertRecords.RecordInput>{
                makeRecord(new List<UpsertRecords.FieldEntry>{ fieldEntry('Name', 'x', 'String') })
            }));
            Assert.fail('Expected exception for missing allOrNone');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('allOrNone'), 'Should mention allOrNone');
        }

        // missing/empty records
        try {
            run(buildInput('Account', true, null, null));
            Assert.fail('Expected exception for missing records');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('records'), 'Should mention records');
        }
        try {
            run(buildInput('Account', true, null, new List<UpsertRecords.RecordInput>()));
            Assert.fail('Expected exception for empty records');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('empty'), 'Should mention empty');
        }

        // records exceed 200
        List<UpsertRecords.RecordInput> bigList = new List<UpsertRecords.RecordInput>();
        for (Integer i = 0; i < 201; i++) {
            bigList.add(makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Name', 'Test', 'String')
            }));
        }
        try {
            run(buildInput('Account', true, null, bigList));
            Assert.fail('Expected exception for records > 200');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('200'), 'Should mention 200 limit');
        }

        // unknown objectApiName
        try {
            run(buildInput('NonExistentObject__xyz', true, null,
                new List<UpsertRecords.RecordInput>{ makeRecord(new List<UpsertRecords.FieldEntry>{
                    fieldEntry('Name', 'x', 'String')
                }) }
            ));
            Assert.fail('Expected exception for unknown object');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('NonExistentObject__xyz'), 'Should mention object name');
        }

        // record with missing/empty fields array
        try {
            run(buildInput('Account', true, null,
                new List<UpsertRecords.RecordInput>{ makeRecord(null) }
            ));
            Assert.fail('Expected exception for missing fields');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fields'), 'Should mention fields');
        }
        try {
            run(buildInput('Account', true, null,
                new List<UpsertRecords.RecordInput>{ makeRecord(new List<UpsertRecords.FieldEntry>()) }
            ));
            Assert.fail('Expected exception for empty fields');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('empty'), 'Should mention empty');
        }

        // missing fieldApiName
        try {
            run(buildInput('Account', true, null,
                new List<UpsertRecords.RecordInput>{ makeRecord(new List<UpsertRecords.FieldEntry>{
                    fieldEntry(null, 'x', 'String')
                }) }
            ));
            Assert.fail('Expected exception for missing fieldApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fieldApiName'), 'Should mention fieldApiName');
        }

        // missing apexType
        try {
            run(buildInput('Account', true, null,
                new List<UpsertRecords.RecordInput>{ makeRecord(new List<UpsertRecords.FieldEntry>{
                    fieldEntry('Name', 'x', null)
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
            run(buildInput('Account', true, 'NonExistentField__xyz',
                new List<UpsertRecords.RecordInput>{ makeRecord(new List<UpsertRecords.FieldEntry>{
                    fieldEntry('Name', 'Test', 'String')
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
            run(buildInput('Account', true, 'Name',
                new List<UpsertRecords.RecordInput>{ makeRecord(new List<UpsertRecords.FieldEntry>{
                    fieldEntry('Name', 'Test', 'String')
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
    // @InvocableVariable does not support a generic Object type, so field values
    // arrive as strings exclusively — every case here reflects that constraint.

    @IsTest
    static void testConvertValue() {
        // null value always returns null regardless of type
        Assert.isNull(UpsertRecords.convertValue(null, 'String',  'f', 0), 'null → null for String');
        Assert.isNull(UpsertRecords.convertValue(null, 'Boolean', 'f', 0), 'null → null for Boolean');
        Assert.isNull(UpsertRecords.convertValue(null, 'Integer', 'f', 0), 'null → null for Integer');
        Assert.isNull(UpsertRecords.convertValue(null, 'Date',    'f', 0), 'null → null for Date');

        // String
        Assert.areEqual('hello', UpsertRecords.convertValue('hello', 'String', 'f', 0));

        // ID — from string
        Account acc = new Account(Name = 'ID Test');
        insert acc;
        Object convertedId = UpsertRecords.convertValue(String.valueOf(acc.Id), 'ID', 'f', 0);
        Assert.areEqual(acc.Id, (Id) convertedId, 'ID from string should match');
        try {
            UpsertRecords.convertValue('not-a-real-id', 'ID', 'f', 0);
            Assert.fail('Expected exception for invalid ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('not a valid Salesforce ID'), 'Should mention invalid ID');
        }

        // Boolean — from string
        Assert.areEqual(true,  UpsertRecords.convertValue('true',  'Boolean', 'f', 0));
        Assert.areEqual(false, UpsertRecords.convertValue('false', 'Boolean', 'f', 0));
        try {
            UpsertRecords.convertValue('yes', 'Boolean', 'f', 0);
            Assert.fail('Expected exception for invalid boolean string');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('boolean'), 'Should mention boolean');
        }

        // Integer
        Assert.areEqual(42, (Integer) UpsertRecords.convertValue('42', 'Integer', 'f', 0));
        try {
            UpsertRecords.convertValue('abc', 'Integer', 'f', 0);
            Assert.fail('Expected exception for invalid integer');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('integer'), 'Should mention Integer');
        }

        // Decimal
        Assert.areEqual(1.5, (Decimal) UpsertRecords.convertValue('1.5', 'Decimal', 'f', 0));
        try {
            UpsertRecords.convertValue('xyz', 'Decimal', 'f', 0);
            Assert.fail('Expected exception for invalid decimal');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('decimal'), 'Should mention Decimal');
        }

        // Long
        Assert.areEqual(100L, (Long) UpsertRecords.convertValue('100', 'Long', 'f', 0));
        try {
            UpsertRecords.convertValue('nope', 'Long', 'f', 0);
            Assert.fail('Expected exception for invalid long');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('long'), 'Should mention Long');
        }

        // Date — ISO YYYY-MM-DD
        Date isoDate = (Date) UpsertRecords.convertValue('2024-06-15', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), isoDate, 'ISO date should parse');
        // Date — MM/DD/YYYY
        Date slashDate = (Date) UpsertRecords.convertValue('06/15/2024', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), slashDate, 'MM/DD/YYYY should parse');
        // Date — DD-MM-YYYY
        Date euDate = (Date) UpsertRecords.convertValue('15-06-2024', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), euDate, 'DD-MM-YYYY should parse');
        try {
            UpsertRecords.convertValue('not-a-date', 'Date', 'f', 0);
            Assert.fail('Expected exception for invalid date');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('date'), 'Should mention date');
        }

        // Datetime — ISO 8601 with Z. Accessors must be the Gmt variants — the running
        // org's default time zone would otherwise shift hour/minute and mask a UTC bug.
        Datetime dt = (Datetime) UpsertRecords.convertValue('2024-06-15T13:30:45Z', 'DateTime', 'f', 0);
        Assert.areEqual(2024, dt.yearGmt(),   'Year should be 2024');
        Assert.areEqual(6,    dt.monthGmt(),  'Month should be 6');
        Assert.areEqual(15,   dt.dayGmt(),    'Day should be 15');
        Assert.areEqual(13,   dt.hourGmt(),   'Hour should be 13');
        Assert.areEqual(30,   dt.minuteGmt(), 'Minute should be 30');
        // Datetime — with milliseconds
        Datetime dtMs = (Datetime) UpsertRecords.convertValue('2024-06-15T13:30:45.000Z', 'DateTime', 'f', 0);
        Assert.areEqual(2024, dtMs.yearGmt(), 'Year should be 2024 (with ms)');

        // Datetime — explicit positive UTC offset (+05:30) must shift to the correct
        // absolute UTC instant via valueOfGmt() + offset arithmetic, not
        // Datetime.valueOf()'s local-time interpretation. Datetime accessor methods
        // (hour/minute/second) always return GMT components, so this is unambiguous
        // regardless of the running org's default time zone — 13:30:45+05:30 is
        // 08:00:45 UTC.
        Datetime dtPosOffset = (Datetime) UpsertRecords.convertValue('2024-06-15T13:30:45+05:30', 'DateTime', 'f', 0);
        Assert.areEqual(8,  dtPosOffset.hourGmt(),   '+05:30 offset should shift to 08:00:45 UTC (hour)');
        Assert.areEqual(0,  dtPosOffset.minuteGmt(), '+05:30 offset should shift to 08:00:45 UTC (minute)');
        Assert.areEqual(45, dtPosOffset.secondGmt(), '+05:30 offset should shift to 08:00:45 UTC (second)');

        // Datetime — explicit negative UTC offset (-05:00): 13:30:45-05:00 is 18:30:45 UTC.
        Datetime dtNegOffset = (Datetime) UpsertRecords.convertValue('2024-06-15T13:30:45-05:00', 'DateTime', 'f', 0);
        Assert.areEqual(18, dtNegOffset.hourGmt(),   '-05:00 offset should shift to 18:30:45 UTC (hour)');
        Assert.areEqual(30, dtNegOffset.minuteGmt(), '-05:00 offset should shift to 18:30:45 UTC (minute)');

        // Datetime — negative offset with fractional seconds present before the offset marker
        Datetime dtNegOffsetMs = (Datetime) UpsertRecords.convertValue('2024-06-15T13:30:45.500-05:00', 'DateTime', 'f', 0);
        Assert.areEqual(18, dtNegOffsetMs.hourGmt(), '-05:00 offset with fractional seconds should still shift correctly');

        // Datetime — Z always maps to a fixed UTC instant regardless of offset math
        Datetime dtZ = (Datetime) UpsertRecords.convertValue('2024-06-15T13:30:45Z', 'DateTime', 'f', 0);
        Assert.areEqual(13, dtZ.hourGmt(), 'Z should map directly to 13:30:45 UTC');

        try {
            UpsertRecords.convertValue('not-a-datetime', 'DateTime', 'f', 0);
            Assert.fail('Expected exception for invalid datetime');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('datetime'), 'Should mention Datetime');
        }

        // Time — HH:mm:ss
        Time t = (Time) UpsertRecords.convertValue('13:30:45', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(13, 30, 45, 0), t, 'Time should parse HH:mm:ss');
        // Time — with trailing Z and milliseconds
        Time tZ = (Time) UpsertRecords.convertValue('09:05:00.000Z', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(9, 5, 0, 0), tZ, 'Time should strip Z and ms');
        // Time — HH:mm (no seconds)
        Time tShort = (Time) UpsertRecords.convertValue('08:00', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(8, 0, 0, 0), tShort, 'Time should handle HH:mm');
        try {
            UpsertRecords.convertValue('not-a-time', 'Time', 'f', 0);
            Assert.fail('Expected exception for invalid time');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('time'), 'Should mention Time');
        }

        // Unsupported type throws
        try {
            UpsertRecords.convertValue('x', 'Blob', 'f', 0);
            Assert.fail('Expected exception for unsupported type');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Blob'), 'Should mention the unsupported type');
        }
    }

    // ─── Insert and update via upsert ────────────────────────────────────────────

    @IsTest
    static void testInsertAndUpdate() {
        // ── Insert: two new Account records (no Id → creates) ──────────────────
        List<UpsertRecords.RecordInput> insertRecords = new List<UpsertRecords.RecordInput>{
            makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Name', 'UpsertTest Alpha', 'String')
            }),
            makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Name', 'UpsertTest Beta',  'String')
            })
        };

        List<Object> insertResult = (List<Object>) run(buildInput('Account', true, null, insertRecords));

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
        List<UpsertRecords.RecordInput> updateRecords = new List<UpsertRecords.RecordInput>{
            makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Id',   id0,                    'ID'),
                fieldEntry('Name', 'UpsertTest Alpha v2',  'String')
            }),
            makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Id',   id1,                    'ID'),
                fieldEntry('Name', 'UpsertTest Beta v2',   'String')
            })
        };

        List<Object> updateResult = (List<Object>) run(buildInput('Account', true, null, updateRecords));

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

    // ─── DML error handling ────────────────────────────────────────────────────────

    @IsTest
    static void testDmlError() {
        // allOrNone=false: one valid record + one record clearing a required
        // field (omitted value → null) — partial success should be returned.
        List<UpsertRecords.RecordInput> partialRecords = new List<UpsertRecords.RecordInput>{
            makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Name', 'UpsertTest Partial OK', 'String')
            }),
            makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Name', null, 'String') // Account.Name is required — will fail
            })
        };

        List<Object> partialResult = (List<Object>) run(buildInput('Account', false, null, partialRecords));

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
    }

    // ─── End-to-end via the real Invocable.Action dispatch path ──────────────────

    @IsTest
    static void testHappyPathViaInvocableAction() {
        // Invocable.Action.setInvocations() cannot coerce a raw List<Object>/Map literal
        // into a nested Apex-defined wrapper type (List<UpsertRecords.RecordInput> whose
        // own "fields" is itself List<FieldEntry>) — the same platform limitation
        // ApexAgentToolExecutor.buildTypedList() works around for real tool calls. The
        // invocation map must carry genuinely-typed objects for such parameters, not maps.
        List<UpsertRecords.RecordInput> records = new List<UpsertRecords.RecordInput>{
            makeRecord(new List<UpsertRecords.FieldEntry>{
                fieldEntry('Name', 'UpsertTest Invocable', 'String')
            })
        };

        Invocable.Action action = Invocable.Action.createCustomAction('apex', 'UpsertRecords');
        action.setInvocations(new List<Map<String, Object>>{
            new Map<String, Object>{
                'objectApiName' => 'Account',
                'allOrNone'     => true,
                'records'       => records
            }
        });

        Test.startTest();
        List<Invocable.Action.Result> results = action.invoke();
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess(), 'Action invocation should succeed');
        Map<String, Object> outputs = results[0].getOutputParameters();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped((String) outputs.get('resultJson'));
        Assert.areEqual(1, parsed.size(), 'Should have one result entry');
        Assert.areEqual(true, ((Map<String, Object>) parsed[0]).get('success'), 'Record should succeed');
    }
}
