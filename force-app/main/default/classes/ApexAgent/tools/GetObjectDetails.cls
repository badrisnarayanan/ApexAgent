@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class GetObjectDetails implements ApexAgentTool {

    public Object execute(Map<String, Object> input) {
        validateInput(input);

        String objectApiName = String.valueOf(input.get('objectApiName')).trim();
        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);

        if (!describe.isAccessible()) {
            return new Map<String, Object>{
                'objectAPIName' => describe.getName(),
                'label'         => describe.getLabel(),
                'isAccessible'  => false,
                'message'       => 'Object is not accessible by the running user'
            };
        }

        Map<String, Object> result = new Map<String, Object>();

        result.put('objectAPIName',  describe.getName());
        result.put('label',          describe.getLabel());
        result.put('isCustom',       describe.isCustom());
        result.put('isAccessible',   describe.isAccessible());
        result.put('isCreateable',   describe.isCreateable());
        result.put('isDeleteable',   describe.isDeletable());
        result.put('isQueryable',    describe.isQueryable());
        result.put('isSearchable',   describe.isSearchable());
        result.put('isUndeleteable', describe.isUndeletable());
        result.put('isUpdateable',   describe.isUpdateable());

        buildFieldData(describe, result);
        buildRecordTypes(describe, result);
        buildChildRelationships(describe, result);

        return result;
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    private void validateInput(Map<String, Object> input) {
        if (input == null) {
            throw new IllegalArgumentException('Input map must not be null');
        }
        if (!input.containsKey('objectApiName')) {
            throw new IllegalArgumentException('Missing required input parameter: objectApiName');
        }
        if (input.get('objectApiName') == null) {
            throw new IllegalArgumentException('Input parameter objectApiName must not be null');
        }
        if (String.isBlank(String.valueOf(input.get('objectApiName')))) {
            throw new IllegalArgumentException('Input parameter objectApiName must not be blank');
        }
    }

    // ─── Fields, required fields, and name field (single pass) ──────────────────

    private void buildFieldData(Schema.DescribeSObjectResult describe, Map<String, Object> result) {
        Map<String, List<List<String>>> fieldsByType = new Map<String, List<List<String>>>();
        List<String> required = new List<String>();
        String nameField = null;

        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = field.getDescribe();

            if (fd.isNameField()) {
                nameField = fd.getName();
            }

            if (!fd.isNillable() && fd.isCreateable() && !fd.isDefaultedOnCreate() && !fd.isAutoNumber()) {
                required.add(fd.getName());
            }

            if (!fd.isAccessible()) {
                continue;
            }

            String soapType = fd.getSoapType().name();
            if (!fieldsByType.containsKey(soapType)) {
                fieldsByType.put(soapType, new List<List<String>>());
            }

            List<String> entry = new List<String>{ fd.getName(), fd.getLabel() };
            List<Schema.SObjectType> referenceTo = fd.getReferenceTo();
            if (referenceTo != null && referenceTo.size() == 1) {
                entry.add(referenceTo[0].getDescribe().getName());
            }

            fieldsByType.get(soapType).add(entry);
        }

        result.put('fields', fieldsByType);
        result.put(
            'fieldsFormat',
            'Fields are grouped by SOAP type (e.g. STRING, ID, DOUBLE, BOOLEAN). '
            + 'Each field entry is [ApiName, Label]. '
            + 'Fields with exactly one lookup target include a third element: [ApiName, Label, LookupObjectApiName].'
        );
        result.put('requiredFields', required);
        result.put('nameField', nameField);
    }

    // ─── Record types ────────────────────────────────────────────────────────────

    private void buildRecordTypes(Schema.DescribeSObjectResult describe, Map<String, Object> result) {
        List<List<String>> recordTypes = new List<List<String>>();
        for (Schema.RecordTypeInfo rtInfo : describe.getRecordTypeInfos()) {
            recordTypes.add(new List<String>{ rtInfo.getName(), rtInfo.getRecordTypeId() });
        }
        result.put('recordTypes', recordTypes);
        result.put('recordTypesFormat', 'Each record type entry is [Name, RecordTypeId].');
    }

    // ─── Child relationships ──────────────────────────────────────────────────────

    private void buildChildRelationships(Schema.DescribeSObjectResult describe, Map<String, Object> result) {
        List<List<String>> childRels = new List<List<String>>();
        for (Schema.ChildRelationship cr : describe.getChildRelationships()) {
            if (cr.getRelationshipName() == null) {
                continue;
            }
            childRels.add(new List<String>{
                cr.getRelationshipName(),
                cr.getChildSObject().getDescribe().getName(),
                cr.getField().getDescribe().getName()
            });
        }
        result.put('childRelationships', childRels);
        result.put('childRelationshipsFormat', 'Each child relationship entry is [RelationshipName, ChildObjectApiName, FieldApiName].');
    }
}
