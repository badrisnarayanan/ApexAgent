@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class UpsertRecords implements ApexAgentTool {

    private static final Integer MAX_RECORDS = 200;

    // ─── Entry point ─────────────────────────────────────────────────────────────

    public Object execute(Map<String, Object> input) {
        validateInput(input);

        String       objectApiName       = (String)       input.get('objectApiName');
        Boolean      allOrNone           = (Boolean)      input.get('allOrNone');
        String       externalIdFieldName = (String)       input.get('externalIdFieldName');
        List<Object> rawRecords          = (List<Object>) input.get('records');

        Schema.SObjectType sObjectType = ApexAgentUtils.getSObjectType(objectApiName);
        List<SObject>      records     = convertRecords(rawRecords, sObjectType);

        Schema.SObjectField externalIdField = null;
        if (String.isNotBlank(externalIdFieldName)) {
            externalIdField = getExternalIdField(sObjectType, externalIdFieldName, objectApiName);
        }

        return performUpsert(records, externalIdField, allOrNone);
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    private void validateInput(Map<String, Object> input) {
        if (input == null) {
            throw new IllegalArgumentException('Input map must not be null');
        }

        if (!input.containsKey('objectApiName') || input.get('objectApiName') == null) {
            throw new IllegalArgumentException('Missing required input parameter: objectApiName');
        }
        if (String.isBlank(String.valueOf(input.get('objectApiName')))) {
            throw new IllegalArgumentException('Input parameter objectApiName must not be blank');
        }

        if (!input.containsKey('allOrNone') || input.get('allOrNone') == null) {
            throw new IllegalArgumentException('Missing required input parameter: allOrNone (expected true or false)');
        }

        if (!input.containsKey('records') || input.get('records') == null) {
            throw new IllegalArgumentException('Missing required input parameter: records');
        }

        List<Object> rawRecords = (List<Object>) input.get('records');
        if (rawRecords.isEmpty()) {
            throw new IllegalArgumentException('Input parameter records must not be empty');
        }
        if (rawRecords.size() > MAX_RECORDS) {
            throw new IllegalArgumentException(
                'Input parameter records exceeds the maximum allowed size of ' + MAX_RECORDS
                + '. Received ' + rawRecords.size() + ' records. Split into smaller batches.'
            );
        }
    }

    // ─── Record conversion ───────────────────────────────────────────────────────

    private List<SObject> convertRecords(List<Object> rawRecords, Schema.SObjectType sObjectType) {
        List<SObject> records = new List<SObject>();
        Integer idx = 0;

        for (Object rawRecord : rawRecords) {
            Map<String, Object> recordMap = (Map<String, Object>) rawRecord;

            Object rawFields = recordMap.get('fields');
            if (rawFields == null) {
                throw new IllegalArgumentException(
                    'Record at index ' + idx + ' is missing the required "fields" array'
                );
            }

            List<Object> fields = (List<Object>) rawFields;
            if (fields.isEmpty()) {
                throw new IllegalArgumentException(
                    'Record at index ' + idx + ' has an empty "fields" array — at least one field is required'
                );
            }

            SObject record = sObjectType.newSObject();

            for (Object rawField : fields) {
                Map<String, Object> fieldMap = (Map<String, Object>) rawField;

                String fieldApiName = (String) fieldMap.get('fieldApiName');
                String apexType     = (String) fieldMap.get('apexType');
                Object value        = fieldMap.get('value');

                if (String.isBlank(fieldApiName)) {
                    throw new IllegalArgumentException(
                        'Record at index ' + idx + ': "fieldApiName" is required and must not be blank'
                    );
                }
                if (String.isBlank(apexType)) {
                    throw new IllegalArgumentException(
                        'Record at index ' + idx + ', field "' + fieldApiName
                        + '": "apexType" is required and must not be blank'
                    );
                }

                Object converted = convertValue(value, apexType, fieldApiName, idx);
                record.put(fieldApiName, converted);
            }

            records.add(record);
            idx++;
        }

        return records;
    }

    // ─── Type conversion ─────────────────────────────────────────────────────────

    @TestVisible
    private Object convertValue(Object value, String apexType, String fieldApiName, Integer recordIdx) {
        if (value == null) {
            return null;
        }

        switch on apexType.toUpperCase() {
            when 'STRING' {
                return String.valueOf(value);
            }
            when 'ID' {
                if (value instanceof Id) {
                    return (Id) value;
                }
                try {
                    return Id.valueOf(String.valueOf(value));
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName + '": "'
                        + value + '" is not a valid Salesforce ID'
                    );
                }
            }
            when 'BOOLEAN' {
                if (value instanceof Boolean) {
                    return (Boolean) value;
                }
                String boolStr = String.valueOf(value).trim().toLowerCase();
                if (boolStr == 'true')  { return true; }
                if (boolStr == 'false') { return false; }
                throw new IllegalArgumentException(
                    'Record ' + recordIdx + ', field "' + fieldApiName
                    + '": cannot convert "' + value + '" to Boolean — expected true or false'
                );
            }
            when 'INTEGER' {
                if (value instanceof Integer) {
                    return (Integer) value;
                }
                try {
                    if (value instanceof Decimal) { return ((Decimal) value).intValue(); }
                    return Integer.valueOf(String.valueOf(value));
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": cannot convert "' + value + '" to Integer'
                    );
                }
            }
            when 'DECIMAL' {
                if (value instanceof Decimal) {
                    return (Decimal) value;
                }
                try {
                    if (value instanceof Integer) { return Decimal.valueOf((Integer) value); }
                    return Decimal.valueOf(String.valueOf(value));
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": cannot convert "' + value + '" to Decimal'
                    );
                }
            }
            when 'LONG' {
                if (value instanceof Long) {
                    return (Long) value;
                }
                try {
                    if (value instanceof Integer) { return Long.valueOf(String.valueOf(value)); }
                    if (value instanceof Decimal) { return ((Decimal) value).longValue(); }
                    return Long.valueOf(String.valueOf(value));
                } catch (Exception e) {
                    throw new IllegalArgumentException(
                        'Record ' + recordIdx + ', field "' + fieldApiName
                        + '": cannot convert "' + value + '" to Long'
                    );
                }
            }
            when 'DATE' {
                if (value instanceof Date) {
                    return (Date) value;
                }
                return parseDate(String.valueOf(value), fieldApiName, recordIdx);
            }
            when 'DATETIME' {
                if (value instanceof Datetime) {
                    return (Datetime) value;
                }
                return parseDatetime(String.valueOf(value), fieldApiName, recordIdx);
            }
            when 'TIME' {
                if (value instanceof Time) {
                    return (Time) value;
                }
                return parseTime(String.valueOf(value), fieldApiName, recordIdx);
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

    private Date parseDate(String value, String fieldApiName, Integer recordIdx) {
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

    private Datetime parseDatetime(String value, String fieldApiName, Integer recordIdx) {
        // Normalize ISO 8601 → Salesforce format (YYYY-MM-DD HH:mm:ss)
        String normalized = value.trim();
        if (normalized.contains('T')) {
            normalized = normalized.replace('T', ' ');
            if (normalized.endsWith('Z')) {
                normalized = normalized.removeEnd('Z');
            } else if (normalized.contains('+')) {
                normalized = normalized.substringBefore('+');
            } else {
                // Handle negative UTC offset (-05:00) that appears after the time portion
                Integer offsetIdx = normalized.lastIndexOf('-');
                if (offsetIdx > 10) {
                    normalized = normalized.substring(0, offsetIdx);
                }
            }
            if (normalized.contains('.')) {
                normalized = normalized.substringBefore('.');
            }
            normalized = normalized.trim();
        }

        try {
            return Datetime.valueOf(normalized);
        } catch (Exception firstEx) {
            try {
                return Datetime.parse(value);
            } catch (Exception secondEx) {
                throw new IllegalArgumentException(
                    'Record ' + recordIdx + ', field "' + fieldApiName
                    + '": cannot parse "' + value
                    + '" as a Datetime. Use ISO 8601 format (e.g. 2024-06-15T13:30:45Z).'
                );
            }
        }
    }

    private Boolean areAllNumeric(List<String> parts) {
        for (String part : parts) {
            if (String.isBlank(part)) { return false; }
            for (Integer i = 0; i < part.length(); i++) {
                Integer c = part.charAt(i);
                if (c < 48 || c > 57) { return false; } // '0'=48, '9'=57
            }
        }
        return true;
    }

    private Time parseTime(String value, String fieldApiName, Integer recordIdx) {
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
    private Schema.SObjectField getExternalIdField(
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

    private Object performUpsert(
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

    private Map<String, Object> buildDmlErrorResponse(DmlException e) {
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
