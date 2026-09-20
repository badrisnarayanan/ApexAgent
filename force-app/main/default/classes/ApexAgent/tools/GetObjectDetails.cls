/**
 * Apex Action tool: describes an SObject's fields, record types, and child relationships.
 */
@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class GetObjectDetails {

    private static final String ENTRY_DELIMITER = '|';

    public class Input {
        @InvocableVariable(required=true label='Object API Name' description='API name of the object to describe (e.g. "Account").')
        public String objectApiName;
    }

    public class Output {
        @InvocableVariable(label='Object API Name' description='API name of the object.')
        public String objectApiName;

        @InvocableVariable(label='Label' description='Label of the object.')
        public String label;

        @InvocableVariable(label='Is Accessible' description='False when the object is not accessible by the running user; all other details are then omitted.')
        public Boolean isAccessible;

        @InvocableVariable(label='Message' description='Explanation when the object is not accessible.')
        public String message;

        @InvocableVariable(label='Is Custom' description='True for a custom object.')
        public Boolean isCustom;

        @InvocableVariable(label='Is Createable' description='True if records can be created.')
        public Boolean isCreateable;

        @InvocableVariable(label='Is Deleteable' description='True if records can be deleted.')
        public Boolean isDeleteable;

        @InvocableVariable(label='Is Queryable' description='True if the object can be queried with SOQL.')
        public Boolean isQueryable;

        @InvocableVariable(label='Is Searchable' description='True if the object can be searched with SOSL.')
        public Boolean isSearchable;

        @InvocableVariable(label='Is Undeleteable' description='True if deleted records can be restored.')
        public Boolean isUndeleteable;

        @InvocableVariable(label='Is Updateable' description='True if records can be updated.')
        public Boolean isUpdateable;

        @InvocableVariable(label='Name Field' description='API name of the field that holds the record name.')
        public String nameField;

        @InvocableVariable(label='Required Fields' description='API names of the fields that must be supplied when creating a record.')
        public List<String> requiredFields;

        @InvocableVariable(label='Fields' description='Accessible fields grouped by SOAP type (e.g. STRING, ID, DOUBLE, BOOLEAN). Each entry is "ApiName|Label"; a field with exactly one lookup target is "ApiName|Label|LookupObjectApiName".')
        public List<FieldGroup> fields;

        @InvocableVariable(label='Record Types' description='Each entry is "Name|RecordTypeId".')
        public List<String> recordTypes;

        @InvocableVariable(label='Child Relationships' description='Each entry is "RelationshipName|ChildObjectApiName|FieldApiName".')
        public List<String> childRelationships;
    }

    public class FieldGroup {
        @InvocableVariable(label='SOAP Type' description='SOAP type shared by every field in this group.')
        public String soapType;

        @InvocableVariable(label='Fields' description='Entries in the format described on the Fields output.')
        public List<String> fields;
    }

    @InvocableMethod(label='Get Object Details' description='Returns full metadata for a Salesforce object: API name, label, CRUD flags, fields (grouped by SOAP type), required fields, name field, record types, and child relationships.\n\nWhen to use:\n\nExploring an object\'s structure before querying or building automation.\nYou wanna know "what fields are on X?", "what are the record types?", or "is this object editable?".\nYou need to understand relationships, lookup targets, or child objects.\n\nCritical usage rules:\n\nIf you do not know the object API name - do not assume - use SearchObjects first if you dont know the exact API Name.\nAlways call this tool first to discover field API names before using GetFieldDetails. You cannot know field API names without it.\nDo not call this multiple times for the same object in a single chat. The output is deterministic and will not change. Cache the results mentally.\n\nResult format: fields are grouped by SOAP type; each field entry is "ApiName|Label", or "ApiName|Label|LookupObjectApiName" when the field has exactly one lookup target. Each recordTypes entry is "Name|RecordTypeId" and each childRelationships entry is "RelationshipName|ChildObjectApiName|FieldApiName".')
    public static List<Output> run(List<Input> inputs) {
        try {
            List<Output> results = new List<Output>();
            for (Input inp : inputs) {
                results.add(processOne(inp));
            }
            return results;
        } catch (Exception e) {
            ApexAgentToolErrorContext.record(e);
            throw e;
        }
    }

    private static Output processOne(Input inp) {
        String objectApiName = ApexAgentToolInput.requireNotBlank(inp.objectApiName, 'objectApiName');
        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);

        Output o = new Output();
        o.objectApiName = describe.getName();
        o.label         = describe.getLabel();

        if (!describe.isAccessible()) {
            o.isAccessible = false;
            o.message      = 'Object is not accessible by the running user';
            return o;
        }

        o.isAccessible   = describe.isAccessible();
        o.isCustom       = describe.isCustom();
        o.isCreateable   = describe.isCreateable();
        o.isDeleteable   = describe.isDeletable();
        o.isQueryable    = describe.isQueryable();
        o.isSearchable   = describe.isSearchable();
        o.isUndeleteable = describe.isUndeletable();
        o.isUpdateable   = describe.isUpdateable();

        buildFieldData(describe, o);
        buildRecordTypes(describe, o);
        buildChildRelationships(describe, o);

        return o;
    }

    // ─── Fields, required fields, and name field (single pass) ──────────────────

    private static void buildFieldData(Schema.DescribeSObjectResult describe, Output o) {
        Map<String, FieldGroup> groupsBySoapType = new Map<String, FieldGroup>();
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
            if (!groupsBySoapType.containsKey(soapType)) {
                FieldGroup soapGroup = new FieldGroup();
                soapGroup.soapType = soapType;
                soapGroup.fields   = new List<String>();
                groupsBySoapType.put(soapType, soapGroup);
            }

            List<String> entry = new List<String>{ fd.getName(), fd.getLabel() };
            List<Schema.SObjectType> referenceTo = fd.getReferenceTo();
            if (referenceTo != null && referenceTo.size() == 1) {
                entry.add(referenceTo[0].getDescribe().getName());
            }

            groupsBySoapType.get(soapType).fields.add(toEntry(entry));
        }

        List<String> soapTypes = new List<String>(groupsBySoapType.keySet());
        soapTypes.sort();
        o.fields = new List<FieldGroup>();
        for (String soapType : soapTypes) {
            o.fields.add(groupsBySoapType.get(soapType));
        }

        o.requiredFields = required;
        o.nameField      = nameField;
    }

    // ─── Record types ────────────────────────────────────────────────────────────

    private static void buildRecordTypes(Schema.DescribeSObjectResult describe, Output o) {
        o.recordTypes = new List<String>();
        for (Schema.RecordTypeInfo rtInfo : describe.getRecordTypeInfos()) {
            o.recordTypes.add(toEntry(new List<String>{ rtInfo.getName(), rtInfo.getRecordTypeId() }));
        }
    }

    // ─── Child relationships ──────────────────────────────────────────────────────

    private static void buildChildRelationships(Schema.DescribeSObjectResult describe, Output o) {
        o.childRelationships = new List<String>();
        for (Schema.ChildRelationship cr : describe.getChildRelationships()) {
            if (cr.getRelationshipName() == null) {
                continue;
            }
            o.childRelationships.add(toEntry(new List<String>{
                cr.getRelationshipName(),
                cr.getChildSObject().getDescribe().getName(),
                cr.getField().getDescribe().getName()
            }));
        }
    }

    // ─── Compact entry encoding ──────────────────────────────────────────────────

    /**
     * Joins the parts of one entry with the delimiter. Entries are sent as compact
     * strings rather than objects so their keys aren't repeated on every entry, which
     * would make this tool's output about 60% larger for an object like Account. A
     * delimiter inside a part (only plausible in a label) would corrupt the entry, so
     * it is replaced with "/".
     */
    @TestVisible
    private static String toEntry(List<String> parts) {
        List<String> safe = new List<String>();
        for (String part : parts) {
            safe.add(part == null ? '' : part.replace(ENTRY_DELIMITER, '/'));
        }
        return String.join(safe, ENTRY_DELIMITER);
    }
}
