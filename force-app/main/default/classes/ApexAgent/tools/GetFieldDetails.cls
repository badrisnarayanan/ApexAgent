@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class GetFieldDetails implements ApexAgentTool {

    public Object execute(Map<String, Object> input) {
        validateInput(input);

        String objectApiName = String.valueOf(input.get('objectApiName')).trim();
        List<String> fieldNames = parseFieldList(input.get('fieldApiNameList'));

        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);

        if (!describe.isAccessible()) {
            return new Map<String, Object>{
                'objectApiName' => describe.getName(),
                'isAccessible'  => false,
                'message'       => 'Object is not accessible by the running user'
            };
        }

        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

        List<Map<String, Object>> fieldDetails = new List<Map<String, Object>>();
        for (String fieldName : fieldNames) {
            fieldDetails.add(buildFieldDetail(fieldMap, fieldName.trim()));
        }

        return new Map<String, Object>{
            'objectApiName' => describe.getName(),
            'fields'        => fieldDetails
        };
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
        if (!input.containsKey('fieldApiNameList') || input.get('fieldApiNameList') == null) {
            throw new IllegalArgumentException('Missing required input parameter: fieldApiNameList');
        }
    }

    // ─── Field list parsing ──────────────────────────────────────────────────────

    private List<String> parseFieldList(Object raw) {
        List<String> result;

        if (raw instanceof List<Object>) {
            result = new List<String>();
            for (Object item : (List<Object>) raw) {
                if (item == null) {
                    throw new IllegalArgumentException('fieldApiNameList must not contain null values');
                }
                result.add(String.valueOf(item));
            }
        } else if (raw instanceof String) {
            try {
                result = (List<String>) JSON.deserialize((String) raw, List<String>.class);
            } catch (Exception e) {
                throw new IllegalArgumentException(
                    'fieldApiNameList string value could not be parsed as a JSON array: ' + (String) raw
                );
            }
        } else {
            throw new IllegalArgumentException(
                'fieldApiNameList must be a list or a JSON array string'
            );
        }

        if (result == null || result.isEmpty()) {
            throw new IllegalArgumentException('fieldApiNameList must not be empty');
        }
        return result;
    }

    // ─── Per-field detail builder ────────────────────────────────────────────────

    private Map<String, Object> buildFieldDetail(
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
