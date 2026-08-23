/**
 * Apex Action tool: describes an SObject's fields, record types, and child relationships.
 */
@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class GetObjectDetails {

    public class Input {
        @InvocableVariable(required=true label='Object API Name' description='API name of the object to describe (e.g. "Account").')
        public String objectApiName;
    }

    public class Output {
        @InvocableVariable(label='Result' description='JSON object with field, record type, and child relationship details.')
        public String resultJson;
    }

    @InvocableMethod(label='Get Object Details' description='Returns full metadata for a Salesforce object: API name, label, CRUD flags, fields (grouped by SOAP type), required fields, name field, record types, and child relationships.\n\nWhen to use:\n\nExploring an object\'s structure before querying or building automation.\nYou wanna know "what fields are on X?", "what are the record types?", or "is this object editable?".\nYou need to understand relationships, lookup targets, or child objects.\n\nCritical usage rules:\n\nIf you do not know the object API name - do not assume - use SearchObjects first if you dont know the exact API Name.\nAlways call this tool first to discover field API names before using GetFieldDetails. You cannot know field API names without it.\nDo not call this multiple times for the same object in a single chat. The output is deterministic and will not change. Cache the results mentally.')
    public static List<Output> run(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(processOne(inp));
        }
        return results;
    }

    private static Output processOne(Input inp) {
        String objectApiName = ApexAgentToolInput.requireNotBlank(inp.objectApiName, 'objectApiName');
        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);

        Output o = new Output();
        if (!describe.isAccessible()) {
            o.resultJson = JSON.serialize(new Map<String, Object>{
                'objectAPIName' => describe.getName(),
                'label'         => describe.getLabel(),
                'isAccessible'  => false,
                'message'       => 'Object is not accessible by the running user'
            });
            return o;
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

        o.resultJson = JSON.serialize(result);
        return o;
    }

    // ─── Fields, required fields, and name field (single pass) ──────────────────

    private static void buildFieldData(Schema.DescribeSObjectResult describe, Map<String, Object> result) {
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

    private static void buildRecordTypes(Schema.DescribeSObjectResult describe, Map<String, Object> result) {
        List<List<String>> recordTypes = new List<List<String>>();
        for (Schema.RecordTypeInfo rtInfo : describe.getRecordTypeInfos()) {
            recordTypes.add(new List<String>{ rtInfo.getName(), rtInfo.getRecordTypeId() });
        }
        result.put('recordTypes', recordTypes);
        result.put('recordTypesFormat', 'Each record type entry is [Name, RecordTypeId].');
    }

    // ─── Child relationships ──────────────────────────────────────────────────────

    private static void buildChildRelationships(Schema.DescribeSObjectResult describe, Map<String, Object> result) {
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
