@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class GetRecordDetails implements ApexAgentTool {

    public Object execute(Map<String, Object> input) {
        validateInput(input);

        String recordIdStr = String.valueOf(input.get('recordId')).trim();
        Id recordId        = parseRecordId(recordIdStr);

        String objectApiName                   = ApexAgentUtils.getObjectApiNameFromId(recordId);
        Schema.DescribeSObjectResult describe  = ApexAgentUtils.getDescribe(objectApiName);

        if (!describe.isAccessible()) {
            return new Map<String, Object>{
                'isAccessible' => false,
                'message'      => 'Object ' + objectApiName + ' is not accessible by the running user'
            };
        }

        List<String> queryFields = buildFieldList(describe);

        String soql = 'SELECT ' + String.join(queryFields, ', ')
                    + ' FROM '  + objectApiName
                    + ' WHERE Id = :recordId';

        List<SObject> results;
        try {
            results = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'recordId' => recordId },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            return new Map<String, Object>{
                'error'   => true,
                'message' => 'Query failed: ' + e.getMessage()
            };
        }

        if (results.isEmpty()) {
            return new Map<String, Object>{
                'found'   => false,
                'message' => 'No record found for Id: ' + recordIdStr
            };
        }

        return JSON.deserializeUntyped(JSON.serialize(results[0]));
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    private void validateInput(Map<String, Object> input) {
        if (input == null) {
            throw new IllegalArgumentException('Input map must not be null');
        }
        if (!input.containsKey('recordId')) {
            throw new IllegalArgumentException('Missing required input parameter: recordId');
        }
        if (input.get('recordId') == null) {
            throw new IllegalArgumentException('Input parameter recordId must not be null');
        }
        if (String.isBlank(String.valueOf(input.get('recordId')))) {
            throw new IllegalArgumentException('Input parameter recordId must not be blank');
        }
    }

    private Id parseRecordId(String recordIdStr) {
        try {
            return Id.valueOf(recordIdStr);
        } catch (Exception e) {
            throw new IllegalArgumentException('recordId is not a valid Salesforce ID: ' + recordIdStr);
        }
    }

    // ─── Field list builder ──────────────────────────────────────────────────────

    private List<String> buildFieldList(Schema.DescribeSObjectResult describe) {
        List<String> fields = new List<String>();

        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = field.getDescribe();

            if (!fd.isAccessible()) {
                continue;
            }
            // Skip long text areas and rich text (HTML-formatted) fields
            if (fd.getType() == Schema.DisplayType.TEXTAREA && fd.getLength() > 255) {
                continue;
            }
            if (fd.isHtmlFormatted()) {
                continue;
            }

            fields.add(fd.getName());

            // Lookup enrichment: custom lookup/master-detail fields end with '__c'
            // Add RelationshipName.NameField so the LLM gets the human-readable label
            if (fd.getType() == Schema.DisplayType.REFERENCE
                    && fd.getName().endsWith('__c')
                    && String.isNotBlank(fd.getRelationshipName())) {

                List<Schema.SObjectType> refs = fd.getReferenceTo();
                if (refs != null && !refs.isEmpty()) {
                    String nameFieldName = ApexAgentUtils.getNameField(refs[0].getDescribe());
                    if (String.isNotBlank(nameFieldName)) {
                        fields.add(fd.getRelationshipName() + '.' + nameFieldName);
                    }
                }
            }
        }

        return fields;
    }

}
