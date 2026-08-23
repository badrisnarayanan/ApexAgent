/**
 * Apex Action tool: describes one or more fields on an SObject.
 */
@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class GetFieldDetails {

    public class Input {
        @InvocableVariable(required=true label='Object API Name' description='API name of the object the fields belong to (e.g. "Account").')
        public String objectApiName;

        @InvocableVariable(required=true label='Field API Name List' description='List of field API names to retrieve details for (e.g. ["Name", "OwnerId"]).')
        public List<String> fieldApiNameList;
    }

    public class Output {
        @InvocableVariable(label='Result' description='JSON object with per-field details (type, required-ness, picklist values, etc.).')
        public String resultJson;
    }

    @InvocableMethod(label='Get Field Details' description='Returns detailed metadata for specific fields on an object: data type, SOAP type, required flag, access levels (createable, updateable, filterable), picklist values, lookup targets, length/precision, and behavioral flags.\n\nWhen to use:\n\nYou need deep metadata on specific fields after discovering their API names.\nYou wanna know about about field types, picklist options, validation requirements, or lookup relationships, access levels\nYou are building a query or automation and need to verify field constraints.\n\nCritical usage rules:\n\nAlways call GetObjectDetails first to discover exact field API names. Do not guess or invent field names.\nIf you don\'t know the object API name, use SearchObjects first to find it.')
    public static List<Output> run(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(processOne(inp));
        }
        return results;
    }

    private static Output processOne(Input inp) {
        String objectApiName = ApexAgentToolInput.requireNotBlank(inp.objectApiName, 'objectApiName');
        List<String> fieldNames = validateFieldList(inp.fieldApiNameList);

        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);

        Output o = new Output();
        if (!describe.isAccessible()) {
            o.resultJson = JSON.serialize(new Map<String, Object>{
                'objectApiName' => describe.getName(),
                'isAccessible'  => false,
                'message'       => 'Object is not accessible by the running user'
            });
            return o;
        }

        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

        List<Map<String, Object>> fieldDetails = new List<Map<String, Object>>();
        for (String fieldName : fieldNames) {
            fieldDetails.add(buildFieldDetail(fieldMap, fieldName.trim()));
        }

        o.resultJson = JSON.serialize(new Map<String, Object>{
            'objectApiName' => describe.getName(),
            'fields'        => fieldDetails
        });
        return o;
    }

    // ─── Input validation ────────────────────────────────────────────────────────

    private static List<String> validateFieldList(List<String> fieldApiNameList) {
        if (fieldApiNameList == null || fieldApiNameList.isEmpty()) {
            throw new IllegalArgumentException('fieldApiNameList must not be empty');
        }
        for (String fieldName : fieldApiNameList) {
            if (String.isBlank(fieldName)) {
                throw new IllegalArgumentException('fieldApiNameList must not contain blank values');
            }
        }
        return fieldApiNameList;
    }

    // ─── Per-field detail builder ────────────────────────────────────────────────

    private static Map<String, Object> buildFieldDetail(
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName
    ) {
        Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());

        if (field == null) {
            return new Map<String, Object>{
                'name'    => fieldName,
                'found'   => false,
                'message' => 'Field not found on object'
            };
        }

        Schema.DescribeFieldResult fd = field.getDescribe();

        if (!fd.isAccessible()) {
            return new Map<String, Object>{
                'name'        => fd.getName(),
                'isAccessible' => false,
                'message'     => 'Field is not accessible by the running user'
            };
        }

        Map<String, Object> detail = new Map<String, Object>();

        // Core identity
        detail.put('name',     fd.getName());
        detail.put('label',    fd.getLabel());
        detail.put('type',     fd.getType().name());
        detail.put('soapType', fd.getSoapType().name());

        // Characteristics
        detail.put('isCustom',     fd.isCustom());
        detail.put('isRequired',   !fd.isNillable() && fd.isCreateable() && !fd.isDefaultedOnCreate() && !fd.isAutoNumber());
        detail.put('isNameField',  fd.isNameField());
        detail.put('isUnique',     fd.isUnique());
        detail.put('isAutoNumber', fd.isAutoNumber());
        detail.put('isCalculated', fd.isCalculated());
        detail.put('isEncrypted',  fd.isEncrypted());
        detail.put('isExternalId', fd.isExternalId());

        // Size
        detail.put('length',    fd.getLength());
        detail.put('precision', fd.getPrecision());
        detail.put('scale',     fd.getScale());

        // Access & DML flags
        detail.put('isAccessible',  fd.isAccessible());
        detail.put('isCreateable',  fd.isCreateable());
        detail.put('isUpdateable',  fd.isUpdateable());
        detail.put('isFilterable',  fd.isFilterable());
        detail.put('isSortable',    fd.isSortable());
        detail.put('isGroupable',   fd.isGroupable());
        detail.put('isNillable',    fd.isNillable());
        detail.put('isCaseSensitive', fd.isCaseSensitive());

        // Behavioral flags
        detail.put('isDefaultedOnCreate',         fd.isDefaultedOnCreate());
        detail.put('isDependentPicklist',          fd.isDependentPicklist());
        detail.put('isRestrictedPicklist',         fd.isRestrictedPicklist());
        detail.put('isFormulaTreatNullNumberAsZero', fd.isFormulaTreatNullNumberAsZero());

        // Extended: lookup references
        List<Schema.SObjectType> referenceTo = fd.getReferenceTo();
        if (referenceTo != null && !referenceTo.isEmpty()) {
            List<String> refs = new List<String>();
            for (Schema.SObjectType ref : referenceTo) {
                refs.add(ref.getDescribe().getName());
            }
            detail.put('lookupReferences', refs);
        }

        // Extended: picklist values
        Schema.DisplayType fieldType = fd.getType();
        if (fieldType == Schema.DisplayType.PICKLIST || fieldType == Schema.DisplayType.MULTIPICKLIST) {
            List<Map<String, Object>> picklistValues = new List<Map<String, Object>>();
            for (Schema.PicklistEntry entry : fd.getPicklistValues()) {
                picklistValues.add(new Map<String, Object>{
                    'label'        => entry.getLabel(),
                    'value'        => entry.getValue(),
                    'isDefault'    => entry.isDefaultValue()
                });
            }
            detail.put('picklistValues', picklistValues);
        }

        return detail;
    }
}
