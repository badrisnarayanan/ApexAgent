@IsTest
private class ApexAgentUpsertRecordsTest {

    // A package object rather than a standard one, so the subscriber org's own
    // validation rules and automation on standard objects can't affect the DML here
    private static final String TOPIC_OBJECT = 'ApexAgent_Topic__c';

    // ─── Helpers ─────────────────────────────────────────────────────────────────

    private static ApexAgentUpsertRecords.FieldEntry fieldEntry(String fieldApiName, String value, String apexType) {
        ApexAgentUpsertRecords.FieldEntry fe = new ApexAgentUpsertRecords.FieldEntry();
        fe.fieldApiName = fieldApiName;
        fe.value = value;
        fe.apexType = apexType;
        return fe;
    }

    private static ApexAgentUpsertRecords.RecordInput makeRecord(List<ApexAgentUpsertRecords.FieldEntry> fields) {
        ApexAgentUpsertRecords.RecordInput ri = new ApexAgentUpsertRecords.RecordInput();
        ri.fields = fields;
        return ri;
    }

    // Topic_API_Name__c is required and unique, so every record that should save
    // needs its own value; passing null makes the record fail on that required field
    private static ApexAgentUpsertRecords.RecordInput topicRecord(String name, String topicApiName) {
        return makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
            fieldEntry('Name', name, 'String'),
            fieldEntry('Topic_API_Name__c', topicApiName, 'String')
        });
    }

    private static ApexAgentUpsertRecords.Input buildInput(
        String objectApiName,
        Boolean allOrNone,
        String externalIdFieldName,
        List<ApexAgentUpsertRecords.RecordInput> records
    ) {
        ApexAgentUpsertRecords.Input inp = new ApexAgentUpsertRecords.Input();
        inp.objectApiName = objectApiName;
        inp.allOrNone = allOrNone;
        inp.externalIdFieldName = externalIdFieldName;
        inp.records = records;
        return inp;
    }

    private static ApexAgentUpsertRecords.Output run(ApexAgentUpsertRecords.Input inp) {
        List<ApexAgentUpsertRecords.Output> out = ApexAgentUpsertRecords.run(new List<ApexAgentUpsertRecords.Input>{ inp });
        return out[0];
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    @IsTest
    static void testInputValidation() {
        // missing/blank objectApiName
        try {
            run(buildInput(null, true, null, new List<ApexAgentUpsertRecords.RecordInput>{
                makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{ fieldEntry('Name', 'x', 'String') })
            }));
            Assert.fail('Expected exception for missing objectApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('objectApiName'), 'Should mention objectApiName');
        }

        // missing allOrNone
        try {
            run(buildInput(TOPIC_OBJECT, null, null, new List<ApexAgentUpsertRecords.RecordInput>{
                makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{ fieldEntry('Name', 'x', 'String') })
            }));
            Assert.fail('Expected exception for missing allOrNone');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('allOrNone'), 'Should mention allOrNone');
        }

        // missing/empty records
        try {
            run(buildInput(TOPIC_OBJECT, true, null, null));
            Assert.fail('Expected exception for missing records');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('records'), 'Should mention records');
        }
        try {
            run(buildInput(TOPIC_OBJECT, true, null, new List<ApexAgentUpsertRecords.RecordInput>()));
            Assert.fail('Expected exception for empty records');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('empty'), 'Should mention empty');
        }

        // records exceed 200
        List<ApexAgentUpsertRecords.RecordInput> bigList = new List<ApexAgentUpsertRecords.RecordInput>();
        for (Integer i = 0; i < 201; i++) {
            bigList.add(makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
                fieldEntry('Name', 'Test', 'String')
            }));
        }
        try {
            run(buildInput(TOPIC_OBJECT, true, null, bigList));
            Assert.fail('Expected exception for records > 200');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('200'), 'Should mention 200 limit');
        }

        // unknown objectApiName
        try {
            run(buildInput('NonExistentObject__xyz', true, null,
                new List<ApexAgentUpsertRecords.RecordInput>{ makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
                    fieldEntry('Name', 'x', 'String')
                }) }
            ));
            Assert.fail('Expected exception for unknown object');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('NonExistentObject__xyz'), 'Should mention object name');
        }

        // record with missing/empty fields array
        try {
            run(buildInput(TOPIC_OBJECT, true, null,
                new List<ApexAgentUpsertRecords.RecordInput>{ makeRecord(null) }
            ));
            Assert.fail('Expected exception for missing fields');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fields'), 'Should mention fields');
        }
        try {
            run(buildInput(TOPIC_OBJECT, true, null,
                new List<ApexAgentUpsertRecords.RecordInput>{ makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>()) }
            ));
            Assert.fail('Expected exception for empty fields');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('empty'), 'Should mention empty');
        }

        // missing fieldApiName
        try {
            run(buildInput(TOPIC_OBJECT, true, null,
                new List<ApexAgentUpsertRecords.RecordInput>{ makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
                    fieldEntry(null, 'x', 'String')
                }) }
            ));
            Assert.fail('Expected exception for missing fieldApiName');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('fieldApiName'), 'Should mention fieldApiName');
        }

        // missing apexType
        try {
            run(buildInput(TOPIC_OBJECT, true, null,
                new List<ApexAgentUpsertRecords.RecordInput>{ makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
                    fieldEntry('Name', 'x', null)
                }) }
            ));
            Assert.fail('Expected exception for missing apexType');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('apexType'), 'Should mention apexType');
        }

        // invalid externalIdFieldName — non-existent field
        try {
            run(buildInput(TOPIC_OBJECT, true, 'NonExistentField__xyz',
                new List<ApexAgentUpsertRecords.RecordInput>{ makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
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
            run(buildInput(TOPIC_OBJECT, true, 'Name',
                new List<ApexAgentUpsertRecords.RecordInput>{ makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
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
        Assert.isNull(ApexAgentUpsertRecords.convertValue(null, 'String',  'f', 0), 'null → null for String');
        Assert.isNull(ApexAgentUpsertRecords.convertValue(null, 'Boolean', 'f', 0), 'null → null for Boolean');
        Assert.isNull(ApexAgentUpsertRecords.convertValue(null, 'Integer', 'f', 0), 'null → null for Integer');
        Assert.isNull(ApexAgentUpsertRecords.convertValue(null, 'Date',    'f', 0), 'null → null for Date');

        // String
        Assert.areEqual('hello', ApexAgentUpsertRecords.convertValue('hello', 'String', 'f', 0));

        // ID — from string
        Object convertedId = ApexAgentUpsertRecords.convertValue(UserInfo.getUserId(), 'ID', 'f', 0);
        Assert.areEqual(UserInfo.getUserId(), (Id) convertedId, 'ID from string should match');
        try {
            ApexAgentUpsertRecords.convertValue('not-a-real-id', 'ID', 'f', 0);
            Assert.fail('Expected exception for invalid ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('not a valid Salesforce ID'), 'Should mention invalid ID');
        }

        // Boolean — from string
        Assert.areEqual(true,  ApexAgentUpsertRecords.convertValue('true',  'Boolean', 'f', 0));
        Assert.areEqual(false, ApexAgentUpsertRecords.convertValue('false', 'Boolean', 'f', 0));
        try {
            ApexAgentUpsertRecords.convertValue('yes', 'Boolean', 'f', 0);
            Assert.fail('Expected exception for invalid boolean string');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('boolean'), 'Should mention boolean');
        }

        // Integer
        Assert.areEqual(42, (Integer) ApexAgentUpsertRecords.convertValue('42', 'Integer', 'f', 0));
        try {
            ApexAgentUpsertRecords.convertValue('abc', 'Integer', 'f', 0);
            Assert.fail('Expected exception for invalid integer');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('integer'), 'Should mention Integer');
        }

        // Decimal
        Assert.areEqual(1.5, (Decimal) ApexAgentUpsertRecords.convertValue('1.5', 'Decimal', 'f', 0));
        try {
            ApexAgentUpsertRecords.convertValue('xyz', 'Decimal', 'f', 0);
            Assert.fail('Expected exception for invalid decimal');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('decimal'), 'Should mention Decimal');
        }

        // Long
        Assert.areEqual(100L, (Long) ApexAgentUpsertRecords.convertValue('100', 'Long', 'f', 0));
        try {
            ApexAgentUpsertRecords.convertValue('nope', 'Long', 'f', 0);
            Assert.fail('Expected exception for invalid long');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('long'), 'Should mention Long');
        }

        // Date — ISO YYYY-MM-DD
        Date isoDate = (Date) ApexAgentUpsertRecords.convertValue('2024-06-15', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), isoDate, 'ISO date should parse');
        // Date — MM/DD/YYYY
        Date slashDate = (Date) ApexAgentUpsertRecords.convertValue('06/15/2024', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), slashDate, 'MM/DD/YYYY should parse');
        // Date — DD-MM-YYYY
        Date euDate = (Date) ApexAgentUpsertRecords.convertValue('15-06-2024', 'Date', 'f', 0);
        Assert.areEqual(Date.newInstance(2024, 6, 15), euDate, 'DD-MM-YYYY should parse');
        try {
            ApexAgentUpsertRecords.convertValue('not-a-date', 'Date', 'f', 0);
            Assert.fail('Expected exception for invalid date');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('date'), 'Should mention date');
        }

        // Datetime — ISO 8601 with Z. Accessors must be the Gmt variants — the running
        // org's default time zone would otherwise shift hour/minute and mask a UTC bug.
        Datetime dt = (Datetime) ApexAgentUpsertRecords.convertValue('2024-06-15T13:30:45Z', 'DateTime', 'f', 0);
        Assert.areEqual(2024, dt.yearGmt(),   'Year should be 2024');
        Assert.areEqual(6,    dt.monthGmt(),  'Month should be 6');
        Assert.areEqual(15,   dt.dayGmt(),    'Day should be 15');
        Assert.areEqual(13,   dt.hourGmt(),   'Hour should be 13');
        Assert.areEqual(30,   dt.minuteGmt(), 'Minute should be 30');
        // Datetime — with milliseconds
        Datetime dtMs = (Datetime) ApexAgentUpsertRecords.convertValue('2024-06-15T13:30:45.000Z', 'DateTime', 'f', 0);
        Assert.areEqual(2024, dtMs.yearGmt(), 'Year should be 2024 (with ms)');

        // Datetime — explicit positive UTC offset (+05:30) must shift to the correct
        // absolute UTC instant via valueOfGmt() + offset arithmetic, not
        // Datetime.valueOf()'s local-time interpretation. Datetime accessor methods
        // (hour/minute/second) always return GMT components, so this is unambiguous
        // regardless of the running org's default time zone — 13:30:45+05:30 is
        // 08:00:45 UTC.
        Datetime dtPosOffset = (Datetime) ApexAgentUpsertRecords.convertValue('2024-06-15T13:30:45+05:30', 'DateTime', 'f', 0);
        Assert.areEqual(8,  dtPosOffset.hourGmt(),   '+05:30 offset should shift to 08:00:45 UTC (hour)');
        Assert.areEqual(0,  dtPosOffset.minuteGmt(), '+05:30 offset should shift to 08:00:45 UTC (minute)');
        Assert.areEqual(45, dtPosOffset.secondGmt(), '+05:30 offset should shift to 08:00:45 UTC (second)');

        // Datetime — explicit negative UTC offset (-05:00): 13:30:45-05:00 is 18:30:45 UTC.
        Datetime dtNegOffset = (Datetime) ApexAgentUpsertRecords.convertValue('2024-06-15T13:30:45-05:00', 'DateTime', 'f', 0);
        Assert.areEqual(18, dtNegOffset.hourGmt(),   '-05:00 offset should shift to 18:30:45 UTC (hour)');
        Assert.areEqual(30, dtNegOffset.minuteGmt(), '-05:00 offset should shift to 18:30:45 UTC (minute)');

        // Datetime — negative offset with fractional seconds present before the offset marker
        Datetime dtNegOffsetMs = (Datetime) ApexAgentUpsertRecords.convertValue('2024-06-15T13:30:45.500-05:00', 'DateTime', 'f', 0);
        Assert.areEqual(18, dtNegOffsetMs.hourGmt(), '-05:00 offset with fractional seconds should still shift correctly');

        // Datetime — Z always maps to a fixed UTC instant regardless of offset math
        Datetime dtZ = (Datetime) ApexAgentUpsertRecords.convertValue('2024-06-15T13:30:45Z', 'DateTime', 'f', 0);
        Assert.areEqual(13, dtZ.hourGmt(), 'Z should map directly to 13:30:45 UTC');

        try {
            ApexAgentUpsertRecords.convertValue('not-a-datetime', 'DateTime', 'f', 0);
            Assert.fail('Expected exception for invalid datetime');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('datetime'), 'Should mention Datetime');
        }

        // Time — HH:mm:ss
        Time t = (Time) ApexAgentUpsertRecords.convertValue('13:30:45', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(13, 30, 45, 0), t, 'Time should parse HH:mm:ss');
        // Time — with trailing Z and milliseconds
        Time tZ = (Time) ApexAgentUpsertRecords.convertValue('09:05:00.000Z', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(9, 5, 0, 0), tZ, 'Time should strip Z and ms');
        // Time — HH:mm (no seconds)
        Time tShort = (Time) ApexAgentUpsertRecords.convertValue('08:00', 'Time', 'f', 0);
        Assert.areEqual(Time.newInstance(8, 0, 0, 0), tShort, 'Time should handle HH:mm');
        try {
            ApexAgentUpsertRecords.convertValue('not-a-time', 'Time', 'f', 0);
            Assert.fail('Expected exception for invalid time');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().containsIgnoreCase('time'), 'Should mention Time');
        }

        // Unsupported type throws
        try {
            ApexAgentUpsertRecords.convertValue('x', 'Blob', 'f', 0);
            Assert.fail('Expected exception for unsupported type');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Blob'), 'Should mention the unsupported type');
        }
    }

    // ─── Insert and update via upsert ────────────────────────────────────────────

    @IsTest
    static void testInsertAndUpdate() {
        // ── Insert: two new Topic records (no Id → creates) ────────────────────
        List<ApexAgentUpsertRecords.RecordInput> insertRecords = new List<ApexAgentUpsertRecords.RecordInput>{
            topicRecord('UpsertTest Alpha', 'upsert_test_alpha'),
            topicRecord('UpsertTest Beta',  'upsert_test_beta')
        };

        ApexAgentUpsertRecords.Output insertOutput = run(buildInput(TOPIC_OBJECT, true, null, insertRecords));

        Assert.areEqual(true, insertOutput.success, 'Overall result should be successful');
        Assert.areEqual(2, insertOutput.results.size(), 'Result should have 2 entries');

        ApexAgentUpsertRecords.RecordResult r0 = insertOutput.results[0];
        ApexAgentUpsertRecords.RecordResult r1 = insertOutput.results[1];
        Assert.areEqual(true, r0.success, 'First record should succeed');
        Assert.areEqual(true, r1.success, 'Second record should succeed');
        Assert.areEqual(true, r0.created, 'First record should be created');
        Assert.areEqual(true, r1.created, 'Second record should be created');
        String id0 = String.valueOf(r0.id);
        String id1 = String.valueOf(r1.id);
        Assert.isNotNull(id0, 'First result should have an id');
        Assert.isNotNull(id1, 'Second result should have an id');

        // ── Update: re-upsert the same records by Id ───────────────────────────
        List<ApexAgentUpsertRecords.RecordInput> updateRecords = new List<ApexAgentUpsertRecords.RecordInput>{
            makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
                fieldEntry('Id',   id0,                    'ID'),
                fieldEntry('Name', 'UpsertTest Alpha v2',  'String')
            }),
            makeRecord(new List<ApexAgentUpsertRecords.FieldEntry>{
                fieldEntry('Id',   id1,                    'ID'),
                fieldEntry('Name', 'UpsertTest Beta v2',   'String')
            })
        };

        List<ApexAgentUpsertRecords.RecordResult> updateResult = run(buildInput(TOPIC_OBJECT, true, null, updateRecords)).results;

        Assert.areEqual(false, updateResult[0].created, 'Record 0 should be updated, not created');
        Assert.areEqual(false, updateResult[1].created, 'Record 1 should be updated, not created');

        // Verify Name was actually updated in the database
        List<ApexAgent_Topic__c> topics = [SELECT Id, Name FROM ApexAgent_Topic__c WHERE Id IN :new List<Id>{
            Id.valueOf(id0), Id.valueOf(id1)
        } ORDER BY Name];
        Assert.areEqual('UpsertTest Alpha v2', topics[0].Name, 'Name should be updated for Alpha');
        Assert.areEqual('UpsertTest Beta v2',  topics[1].Name, 'Name should be updated for Beta');
    }

    // ─── DML error handling ────────────────────────────────────────────────────────

    @IsTest
    static void testDmlError() {
        // allOrNone=false: one valid record + one record leaving a required
        // field null — partial success should be returned. The failure comes from
        // Topic_API_Name__c rather than Name, since a blank custom-object Name is
        // filled in by the platform instead of being rejected.
        List<ApexAgentUpsertRecords.RecordInput> partialRecords = new List<ApexAgentUpsertRecords.RecordInput>{
            topicRecord('UpsertTest Partial OK',   'upsert_test_partial_ok'),
            topicRecord('UpsertTest Partial Fail', null)
        };

        ApexAgentUpsertRecords.Output partialOutput = run(buildInput(TOPIC_OBJECT, false, null, partialRecords));
        List<ApexAgentUpsertRecords.RecordResult> partialResult = partialOutput.results;

        Assert.areEqual(false, partialOutput.success, 'Overall result should be unsuccessful when any record fails');
        Assert.areEqual(2, partialResult.size(), 'Should have 2 result entries');

        Integer successCt = 0;
        Integer failCount = 0;
        Boolean foundErrors = false;
        for (ApexAgentUpsertRecords.RecordResult det : partialResult) {
            if (det.success == true) {
                successCt++;
            } else {
                failCount++;
                Assert.isFalse(det.errors.isEmpty(), 'Errors list should not be empty');
                Assert.isNotNull(det.errors[0].message,    'Error should have message');
                Assert.isNotNull(det.errors[0].statusCode, 'Error should have statusCode');
                foundErrors = true;
            }
        }
        Assert.isTrue(successCt >= 1, 'At least one record should succeed');
        Assert.isTrue(failCount  >= 1, 'At least one record should fail');
        Assert.isTrue(foundErrors,     'At least one result entry should have errors');

        // The failing record sits in the middle of the batch so a wrong index can't
        // coincide with the right one.
        List<ApexAgentUpsertRecords.RecordInput> middleFails = new List<ApexAgentUpsertRecords.RecordInput>{
            topicRecord('UpsertTest Idx A', 'upsert_test_idx_a'),
            topicRecord('UpsertTest Idx B', null),
            topicRecord('UpsertTest Idx C', 'upsert_test_idx_c')
        };

        // allOrNone=false: the per-record error carries the record's index, and a failed
        // record is not reported as created
        ApexAgentUpsertRecords.Output partial = run(buildInput(TOPIC_OBJECT, false, null, middleFails));
        Assert.areEqual(3, partial.results.size(), 'One result per input record');
        Assert.areEqual(true,  partial.results[0].created, 'Record 0 was inserted');
        Assert.areEqual(true,  partial.results[2].created, 'Record 2 was inserted');
        Assert.areNotEqual(true, partial.results[1].created, 'A failed record must not be reported as created');
        Assert.isNull(partial.results[1].id, 'A failed record has no id');
        Assert.areEqual(1, partial.results[1].errors[0].dmlIndex, 'Per-record error must carry the failing record index');
        Assert.isNull(partial.results[0].errors, 'Successful records have no errors');

        // allOrNone=true: the whole operation fails and dmlIndex is the failing record's
        // position in the input, not the position within the error list
        List<ApexAgentUpsertRecords.RecordInput> allOrNoneBatch = new List<ApexAgentUpsertRecords.RecordInput>{
            topicRecord('UpsertTest Rollback A', 'upsert_test_rollback_a'),
            topicRecord('UpsertTest Rollback B', null),
            topicRecord('UpsertTest Rollback C', 'upsert_test_rollback_c')
        };
        ApexAgentUpsertRecords.Output all = run(buildInput(TOPIC_OBJECT, true, null, allOrNoneBatch));
        Assert.areEqual(false, all.success, 'allOrNone failure');
        Assert.isNull(all.results, 'No per-record results when the whole operation failed');
        Assert.areEqual(1, all.dmlErrors.size(), 'One failing record');
        Assert.areEqual(1, all.dmlErrors[0].dmlIndex, 'dmlIndex must be the failing record\'s index in the input');
        Assert.areEqual(0, [SELECT COUNT() FROM ApexAgent_Topic__c WHERE Name LIKE 'UpsertTest Rollback%'], 'allOrNone must roll everything back');
    }

    // ─── End-to-end via the real Invocable.Action dispatch path ──────────────────

    @IsTest
    static void testHappyPathViaInvocableAction() {
        // Invocable.Action.setInvocations() cannot coerce a raw List<Object>/Map literal
        // into a nested Apex-defined wrapper type (List<ApexAgentUpsertRecords.RecordInput> whose
        // own "fields" is itself List<FieldEntry>) — the same platform limitation
        // ApexAgentToolExecutor.buildTypedList() works around for real tool calls. The
        // invocation map must carry genuinely-typed objects for such parameters, not maps.
        List<ApexAgentUpsertRecords.RecordInput> records = new List<ApexAgentUpsertRecords.RecordInput>{
            topicRecord('UpsertTest Invocable', 'upsert_test_invocable')
        };

        Invocable.Action action = Invocable.Action.createCustomAction('apex', 'ApexAgentUpsertRecords');
        action.setInvocations(new List<Map<String, Object>>{
            new Map<String, Object>{
                'objectApiName' => TOPIC_OBJECT,
                'allOrNone'     => true,
                'records'       => records
            }
        });

        Test.startTest();
        List<Invocable.Action.Result> results = action.invoke();
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess(), 'Action invocation should succeed');
        Map<String, Object> outputs = results[0].getOutputParameters();
        Assert.areEqual(true, outputs.get('success'), 'Overall result should be successful');
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(JSON.serialize(outputs.get('results')));
        Assert.areEqual(1, parsed.size(), 'Should have one result entry');
        Assert.areEqual(true, ((Map<String, Object>) parsed[0]).get('success'), 'Record should succeed');
    }
}
