/**
 * Apex Action tool: inserts or updates records via Database.upsert.
 *
 * Field values arrive as strings (@InvocableVariable does not support a generic
 * Object type), converted per the caller-supplied apexType. Omitting a field's
 * value (or passing null) explicitly clears that field on the record.
 */
@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class UpsertRecords {

    private static final Integer MAX_RECORDS = 200;

    public class FieldEntry {
        @InvocableVariable(required=true label='Field Api Name' description='API name of the field (e.g. "Name", "Amount__c", "CloseDate").')
        public String fieldApiName;

        @InvocableVariable(required=false label='Value' description='The value to set, always as a string (e.g. "42", "true", "2024-06-15") — converted per apexType. Omit to explicitly clear the field.')
        public String value;

        @InvocableVariable(required=true label='Apex Type' description='Apex data type used to convert value before setting it on the record. Valid values: String, Boolean, Integer, Decimal, Date, DateTime, ID, Time, Long.')
        public String apexType;
    }

    public class RecordInput {
        @InvocableVariable(required=true label='Fields' description='Field values to set on this record.')
        public List<FieldEntry> fields;
    }

    public class Input {
        @InvocableVariable(required=true label='Object API Name' description='API name of the object to upsert (e.g. "Account").')
        public String objectApiName;

        @InvocableVariable(required=true label='All Or None' description='If true, the entire operation rolls back on any record failure. If false, partial success is allowed and per-record errors are returned.')
        public Boolean allOrNone;

        @InvocableVariable(required=false label='External Id Field Name' description='API name of the external ID field to upsert on. Omit to upsert by the standard Id field.')
        public String externalIdFieldName;

        @InvocableVariable(required=true label='Records' description='Records to upsert (maximum 200 per call).')
        public List<RecordInput> records;
    }

    public class Output {
        @InvocableVariable(label='Result' description='JSON array of per-record DML results (id/success/errors), or a structured error object if the whole operation failed.')
        public String resultJson;
    }

    @InvocableMethod(label='Upsert Records' description='Creates new records or updates existing ones in a single operation. Supports up to 200 records per call. Returns upsert results with success/error status per record.\n\nCritical usage rules:\n- Always confirm with the user before executing — this modifies data.\n- Always use GetObjectDetails first to discover field API names and required fields.\n- Always verify field types using GetFieldDetails if unsure about the Apex type.\n- Each record must include Id or an external ID field to update existing records. Without either, new records are always created.\n- Max 200 records per call — split larger batches.')
    public static List<Output> run(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(processOne(inp));
        }
        return results;
    }

    private static Output processOne(Input inp) {
        validateInput(inp);

        Schema.SObjectType sObjectType = ApexAgentUtils.getSObjectType(inp.objectApiName);
        List<SObject> records = convertRecords(inp.records, sObjectType);

        Schema.SObjectField externalIdField = null;
        if (String.isNotBlank(inp.externalIdFieldName)) {
            externalIdField = getExternalIdField(sObjectType, inp.externalIdFieldName, inp.objectApiName);
        }

        Output o = new Output();
        o.resultJson = JSON.serialize(performUpsert(records, externalIdField, inp.allOrNone));
        return o;
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    private static void validateInput(Input inp) {
        ApexAgentToolInput.requireNotBlank(inp.objectApiName, 'objectApiName');
        if (inp.allOrNone == null) {
            throw new IllegalArgumentException('Missing required input parameter: allOrNone (expected true or false)');
        }
        if (inp.records == null || inp.records.isEmpty()) {
            throw new IllegalArgumentException('Input parameter records must not be empty');
        }
        if (inp.records.size() > MAX_RECORDS) {
            throw new IllegalArgumentException(
                'Input parameter records exceeds the maximum allowed size of ' + MAX_RECORDS
                + '. Received ' + inp.records.size() + ' records. Split into smaller batches.'
            );
        }
    }

    // ─── Record conversion ───────────────────────────────────────────────────────

    private static List<SObject> convertRecords(List<RecordInput> recordInputs, Schema.SObjectType sObjectType) {
        List<SObject> records = new List<SObject>();
        Integer idx = 0;

        for (RecordInput ri : recordInputs) {
            if (ri.fields == null || ri.fields.isEmpty()) {
                throw new IllegalArgumentException(
                    'Record at index ' + idx + ' has an empty "fields" array — at least one field is required'
                );
            }

            SObject record = sObjectType.newSObject();
            for (FieldEntry fe : ri.fields) {
                String fieldApiName = ApexAgentToolInput.requireNotBlank(
                    fe.fieldApiName, 'records[' + idx + '].fields.fieldApiName'
                );
                String apexType = ApexAgentToolInput.requireNotBlank(
                    fe.apexType, 'records[' + idx + '].fields.apexType'
                );
                record.put(fieldApiName, convertValue(fe.value, apexType, fieldApiName, idx));
            }

            records.add(record);
            idx++;
        }

        return records;
    }

    // ─── Type conversion ─────────────────────────────────────────────────────────

    @TestVisible
    private static Object convertValue(String value, String apexType, String fieldApiName, Integer recordIdx) {
        if (value == null) {
            return null;
        }

        switch on apexType.toUpperCase() {
            when 'STRING' {
                return value;
            }
            when 'ID' {
                try {
                    return Id.valueOf(value);
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName + '": "'
                        + value + '" is not a valid Salesforce ID'
                    );
                }
            }
            when 'BOOLEAN' {
                String boolStr = value.trim().toLowerCase();
                if (boolStr == 'true')  { return true; }
                if (boolStr == 'false') { return false; }
                throw new IllegalArgumentException(
                    'Record ' + recordIdx + ', field "' + fieldApiName
                    + '": cannot convert "' + value + '" to Boolean — expected true or false'
                );
            }
            when 'INTEGER' {
                try {
                    return Integer.valueOf(value);
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": cannot convert "' + value + '" to Integer'
                    );
                }
            }
            when 'DECIMAL' {
                try {
                    return Decimal.valueOf(value);
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": cannot convert "' + value + '" to Decimal'
                    );
                }
            }
            when 'LONG' {
                try {
                    return Long.valueOf(value);
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": cannot convert "' + value + '" to Long'
                    );
                }
            }
            when 'DATE' {
                return parseDate(value, fieldApiName, recordIdx);
            }
            when 'DATETIME' {
                return parseDatetime(value, fieldApiName, recordIdx);
            }
            when 'TIME' {
                return parseTime(value, fieldApiName, recordIdx);
            }
            when else {
                throw new IllegalArgumentException(
                    'Record ' + recordIdx + ', field "' + fieldApiName
                    + '": unsupported apexType "' + apexType
                    + '". Valid values: String, Boolean, Integer, Decimal, Date, DateTime, ID, Time, Long'
                );
            }
        }
    }

    // ─── Date / Datetime / Time parsers ──────────────────────────────────────────

    private static Date parseDate(String value, String fieldApiName, Integer recordIdx) {
        String v = value.trim();

        // 1. YYYY-MM-DD (ISO) — length 10, dash separator, 4-char year, no slash
        if (v.length() == 10 && v.contains('-') && !v.contains('/') && v.indexOf('-') == 4) {
            try {
                return Date.valueOf(v);
            } catch (Exception e) {
                throw new IllegalArgumentException(
                    'Record ' + recordIdx + ', field "' + fieldApiName
                    + '": "' + value + '" matches YYYY-MM-DD format but contains an invalid date'
                    + ' (e.g. month 13 or day 32). Correct the value and retry.'
                );
            }
        }

        // 2. MM/DD/YYYY — detected by presence of '/'
        if (v.contains('/')) {
            List<String> p = v.split('/');
            if (p.size() == 3 && areAllNumeric(p)) {
                try {
                    return Date.newInstance(
                        Integer.valueOf(p[2]),
                        Integer.valueOf(p[0]),
                        Integer.valueOf(p[1])
                    );
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": "' + value + '" looks like MM/DD/YYYY but contains an invalid date.'
                        + ' Correct the value and retry.'
                    );
                }
            }
        }

        // 3. DD-MM-YYYY — length 10, '-' separator, day occupies first 2 chars
        if (v.length() == 10 && v.contains('-')) {
            List<String> p = v.split('-');
            if (p.size() == 3 && p[0].length() == 2 && areAllNumeric(p)) {
                try {
                    return Date.newInstance(
                        Integer.valueOf(p[2]),
                        Integer.valueOf(p[1]),
                        Integer.valueOf(p[0])
                    );
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": "' + value + '" looks like DD-MM-YYYY but contains an invalid date.'
                        + ' Correct the value and retry.'
                    );
                }
            }
        }

        throw new IllegalArgumentException(
            'Record ' + recordIdx + ', field "' + fieldApiName
            + '": cannot parse "' + value + '" as a Date.'
            + ' Use YYYY-MM-DD format (e.g. 2024-06-15).'
        );
    }

    private static Datetime parseDatetime(String value, String fieldApiName, Integer recordIdx) {
        String trimmed = value.trim();
        if (!trimmed.contains('T')) {
            return parseNaiveDatetime(trimmed, value, fieldApiName, recordIdx);
        }
        return parseIso8601Datetime(trimmed, value, fieldApiName, recordIdx);
    }

    /**
     * Parses a 'T'-delimited ISO 8601 datetime. A trailing 'Z' or an explicit +/-HH:MM
     * offset marks the string as UTC/zoned — those are parsed with Datetime.valueOfGmt()
     * (with offset arithmetic applied), never Datetime.valueOf(), since valueOf()
     * interprets its input in the running user's local time zone and would silently
     * shift a UTC timestamp by the org/user's offset. A string with no zone marker at
     * all is genuinely naive and falls back to local-time parsing.
     */
    private static Datetime parseIso8601Datetime(String trimmed, String original, String fieldApiName, Integer recordIdx) {
        String body = trimmed.replace('T', ' ');
        Integer offsetSeconds = 0;
        Boolean hasZoneMarker = false;

        if (body.endsWith('Z')) {
            hasZoneMarker = true;
            body = body.removeEnd('Z');
        } else {
            // Search only the time portion (index > 10 skips the date's own '-' separators,
            // e.g. the dashes in "2024-06-15") for an explicit +HH:MM / -HH:MM offset.
            Integer plusIdx = body.indexOf('+', 10);
            if (plusIdx != -1) {
                hasZoneMarker = true;
                offsetSeconds = parseOffsetSeconds(body.substring(plusIdx), original, fieldApiName, recordIdx);
                body = body.substring(0, plusIdx);
            } else {
                Integer minusIdx = body.lastIndexOf('-');
                if (minusIdx > 10) {
                    hasZoneMarker = true;
                    offsetSeconds = parseOffsetSeconds(body.substring(minusIdx), original, fieldApiName, recordIdx);
                    body = body.substring(0, minusIdx);
                }
            }
        }

        if (body.contains('.')) {
            body = body.substringBefore('.');
        }
        body = body.trim();

        if (!hasZoneMarker) {
            return parseNaiveDatetime(body, original, fieldApiName, recordIdx);
        }

        try {
            Datetime gmt = Datetime.valueOfGmt(body);
            return offsetSeconds != 0 ? gmt.addSeconds(-offsetSeconds) : gmt;
        } catch (Exception e) {
            throw new IllegalArgumentException(
                'Record ' + recordIdx + ', field "' + fieldApiName
                + '": cannot parse "' + original
                + '" as a Datetime. Use ISO 8601 format (e.g. 2024-06-15T13:30:45Z).'
            );
        }
    }

    private static Integer parseOffsetSeconds(String offsetStr, String original, String fieldApiName, Integer recordIdx) {
        try {
            Integer sign = offsetStr.startsWith('-') ? -1 : 1;
            List<String> parts = offsetStr.substring(1).split(':');
            Integer hh = Integer.valueOf(parts[0]);
            Integer mm = parts.size() > 1 ? Integer.valueOf(parts[1]) : 0;
            return sign * (hh * 3600 + mm * 60);
        } catch (Exception e) {
            throw new IllegalArgumentException(
                'Record ' + recordIdx + ', field "' + fieldApiName
                + '": cannot parse the UTC offset in "' + original + '".'
            );
        }
    }

    private static Datetime parseNaiveDatetime(String body, String original, String fieldApiName, Integer recordIdx) {
        try {
            return Datetime.valueOf(body);
        } catch (Exception firstEx) {
            try {
                return Datetime.parse(original);
            } catch (Exception secondEx) {
                throw new IllegalArgumentException(
                    'Record ' + recordIdx + ', field "' + fieldApiName
                    + '": cannot parse "' + original
                    + '" as a Datetime. Use ISO 8601 format (e.g. 2024-06-15T13:30:45Z).'
                );
            }
        }
    }

    private static Boolean areAllNumeric(List<String> parts) {
        for (String part : parts) {
            if (String.isBlank(part)) { return false; }
            for (Integer i = 0; i < part.length(); i++) {
                Integer c = part.charAt(i);
                if (c < 48 || c > 57) { return false; } // '0'=48, '9'=57
            }
        }
        return true;
    }

    private static Time parseTime(String value, String fieldApiName, Integer recordIdx) {
        try {
            String s = value.trim();
            if (s.endsWith('Z')) {
                s = s.removeEnd('Z');
            }
            if (s.contains('.')) {
                s = s.substringBefore('.');
            }
            List<String> parts = s.split(':');
            if (parts.size() < 2) {
                throw new IllegalArgumentException('Too few time components');
            }
            Integer hour   = Integer.valueOf(parts[0]);
            Integer minute = Integer.valueOf(parts[1]);
            Integer second = parts.size() >= 3 ? Integer.valueOf(parts[2]) : 0;
            return Time.newInstance(hour, minute, second, 0);
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException(
                'Record ' + recordIdx + ', field "' + fieldApiName
                + '": cannot parse "' + value + '" as a Time. Use HH:mm:ss format (e.g. 13:30:45).'
            );
        }
    }

    // ─── External ID field resolution ────────────────────────────────────────────

    @TestVisible
    private static Schema.SObjectField getExternalIdField(
        Schema.SObjectType sObjectType,
        String fieldName,
        String objectApiName
    ) {
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
        String fieldNameLower = fieldName.toLowerCase();

        if (!fieldMap.containsKey(fieldNameLower)) {
            throw new IllegalArgumentException(
                'External ID field "' + fieldName + '" does not exist on ' + objectApiName
                + '. Verify the field API name and try again.'
            );
        }

        Schema.DescribeFieldResult fd = fieldMap.get(fieldNameLower).getDescribe();
        if (!fd.isExternalId() && fd.getType() != Schema.DisplayType.ID) {
            throw new IllegalArgumentException(
                'Field "' + fieldName + '" on ' + objectApiName
                + ' is not marked as an External ID. Only fields with isExternalId=true (or the standard Id field) '
                + 'can be used as the upsert key.'
            );
        }

        return fieldMap.get(fieldNameLower);
    }

    // ─── DML execution ───────────────────────────────────────────────────────────

    private static Object performUpsert(
        List<SObject> records,
        Schema.SObjectField externalIdField,
        Boolean allOrNone
    ) {
        List<Database.UpsertResult> results;
        try {
            if (externalIdField != null) {
                results = Database.upsert(records, externalIdField, allOrNone, AccessLevel.USER_MODE);
            } else {
                results = Database.upsert(records, allOrNone, AccessLevel.USER_MODE);
            }
        } catch (DmlException e) {
            return buildDmlErrorResponse(e);
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error'   => e.getMessage()
            };
        }

        return JSON.deserializeUntyped(JSON.serialize(results));
    }

    private static Map<String, Object> buildDmlErrorResponse(DmlException e) {
        List<Map<String, Object>> dmlErrors = new List<Map<String, Object>>();
        for (Integer i = 0; i < e.getNumDml(); i++) {
            dmlErrors.add(new Map<String, Object>{
                'dmlIndex'   => i,
                'recordId'   => e.getDmlId(i) != null ? String.valueOf(e.getDmlId(i)) : null,
                'message'    => e.getDmlMessage(i),
                'statusCode' => String.valueOf(e.getDmlStatusCode(i)),
                'statusType' => e.getDmlType(i) != null ? String.valueOf(e.getDmlType(i)) : null,
                'fieldNames' => e.getDmlFieldNames(i)
            });
        }
        return new Map<String, Object>{
            'success'   => false,
            'error'     => 'DML operation failed: ' + e.getMessage(),
            'dmlErrors' => dmlErrors
        };
    }
}
