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
        @InvocableVariable(label='Object API Name' description='API name of the object the fields belong to.')
        public String objectApiName;

        @InvocableVariable(label='Is Accessible' description='False when the object is not accessible by the running user; fields is then omitted.')
        public Boolean isAccessible;

        @InvocableVariable(label='Message' description='Explanation when the object is not accessible.')
        public String message;

        @InvocableVariable(label='Fields' description='Details for each requested field, in request order.')
        public List<FieldDetail> fields;
    }

    public class PicklistValue {
        @InvocableVariable(label='Label' description='Display label of the picklist entry.')
        public String label;

        @InvocableVariable(label='Value' description='API value of the picklist entry.')
        public String value;

        @InvocableVariable(label='Is Default' description='True if this entry is the default value.')
        public Boolean isDefault;
    }

    public class FieldDetail {
        @InvocableVariable(label='Name' description='Field API name.')
        public String name;

        @InvocableVariable(label='Found' description='False when the field does not exist on the object; all other details are then omitted.')
        public Boolean found;

        @InvocableVariable(label='Message' description='Explanation when the field was not found or is not accessible.')
        public String message;

        @InvocableVariable(label='Label' description='Field label.')
        public String label;

        @InvocableVariable(label='Type' description='Schema.DisplayType name (e.g. STRING, PICKLIST, REFERENCE).')
        public String type;

        @InvocableVariable(label='SOAP Type' description='Schema.SoapType name (e.g. STRING, ID, DOUBLE).')
        public String soapType;

        @InvocableVariable(label='Is Custom' description='True for a custom field.')
        public Boolean isCustom;

        @InvocableVariable(label='Is Required' description='True if a value must be supplied when creating a record.')
        public Boolean isRequired;

        @InvocableVariable(label='Is Name Field' description='True if this is the object\'s name field.')
        public Boolean isNameField;

        @InvocableVariable(label='Is Unique' description='True if values must be unique.')
        public Boolean isUnique;

        @InvocableVariable(label='Is Auto Number' description='True for an auto-number field.')
        public Boolean isAutoNumber;

        @InvocableVariable(label='Is Calculated' description='True for a formula or roll-up field.')
        public Boolean isCalculated;

        @InvocableVariable(label='Is Encrypted' description='True for an encrypted field.')
        public Boolean isEncrypted;

        @InvocableVariable(label='Is External Id' description='True if the field is an external ID.')
        public Boolean isExternalId;

        @InvocableVariable(label='Length' description='Maximum length for text fields.')
        public Integer length;

        @InvocableVariable(label='Precision' description='Total digits for numeric fields.')
        public Integer precision;

        @InvocableVariable(label='Scale' description='Digits right of the decimal point for numeric fields.')
        public Integer scale;

        @InvocableVariable(label='Is Accessible' description='True if the running user can read the field; false means all other details are omitted.')
        public Boolean isAccessible;

        @InvocableVariable(label='Is Createable' description='True if the field can be set on create.')
        public Boolean isCreateable;

        @InvocableVariable(label='Is Updateable' description='True if the field can be changed on update.')
        public Boolean isUpdateable;

        @InvocableVariable(label='Is Filterable' description='True if the field can be used in a WHERE clause.')
        public Boolean isFilterable;

        @InvocableVariable(label='Is Sortable' description='True if the field can be used in ORDER BY.')
        public Boolean isSortable;

        @InvocableVariable(label='Is Groupable' description='True if the field can be used in GROUP BY.')
        public Boolean isGroupable;

        @InvocableVariable(label='Is Nillable' description='True if the field may be null.')
        public Boolean isNillable;

        @InvocableVariable(label='Is Case Sensitive' description='True if values are case sensitive.')
        public Boolean isCaseSensitive;

        @InvocableVariable(label='Is Defaulted On Create' description='True if Salesforce supplies a default when none is given.')
        public Boolean isDefaultedOnCreate;

        @InvocableVariable(label='Is Dependent Picklist' description='True if the picklist depends on a controlling field.')
        public Boolean isDependentPicklist;

        @InvocableVariable(label='Is Restricted Picklist' description='True if only listed picklist values are allowed.')
        public Boolean isRestrictedPicklist;

        @InvocableVariable(label='Is Formula Treat Null Number As Zero' description='True if a formula treats a null number as zero.')
        public Boolean isFormulaTreatNullNumberAsZero;

        @InvocableVariable(label='Lookup References' description='API names of the objects a lookup field can point to.')
        public List<String> lookupReferences;

        @InvocableVariable(label='Picklist Values' description='Entries of a picklist or multi-select picklist field.')
        public List<PicklistValue> picklistValues;
    }

    @InvocableMethod(label='Get Field Details' description='Returns detailed metadata for specific fields on an object: data type, SOAP type, required flag, access levels (createable, updateable, filterable), picklist values, lookup targets, length/precision, and behavioral flags.\n\nWhen to use:\n\nYou need deep metadata on specific fields after discovering their API names.\nYou wanna know about about field types, picklist options, validation requirements, or lookup relationships, access levels\nYou are building a query or automation and need to verify field constraints.\n\nCritical usage rules:\n\nAlways call GetObjectDetails first to discover exact field API names. Do not guess or invent field names.\nIf you don\'t know the object API name, use SearchObjects first to find it.')
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
        List<String> fieldNames = validateFieldList(inp.fieldApiNameList);

        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);

        Output o = new Output();
        o.objectApiName = describe.getName();

        if (!describe.isAccessible()) {
            o.isAccessible = false;
            o.message      = 'Object is not accessible by the running user';
            return o;
        }

        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

        o.fields = new List<FieldDetail>();
        for (String fieldName : fieldNames) {
            o.fields.add(buildFieldDetail(fieldMap, fieldName.trim()));
        }
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

    private static FieldDetail buildFieldDetail(
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName
    ) {
        FieldDetail detail = new FieldDetail();
        Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());

        if (field == null) {
            detail.name    = fieldName;
            detail.found   = false;
            detail.message = 'Field not found on object';
            return detail;
        }

        Schema.DescribeFieldResult fd = field.getDescribe();

        if (!fd.isAccessible()) {
            detail.name         = fd.getName();
            detail.isAccessible = false;
            detail.message      = 'Field is not accessible by the running user';
            return detail;
        }

        // Core identity
        detail.name     = fd.getName();
        detail.label    = fd.getLabel();
        detail.type     = fd.getType().name();
        detail.soapType = fd.getSoapType().name();

        // Characteristics
        detail.isCustom     = fd.isCustom();
        detail.isRequired   = !fd.isNillable() && fd.isCreateable() && !fd.isDefaultedOnCreate() && !fd.isAutoNumber();
        detail.isNameField  = fd.isNameField();
        detail.isUnique     = fd.isUnique();
        detail.isAutoNumber = fd.isAutoNumber();
        detail.isCalculated = fd.isCalculated();
        detail.isEncrypted  = fd.isEncrypted();
        detail.isExternalId = fd.isExternalId();

        // Size
        detail.length    = fd.getLength();
        detail.precision = fd.getPrecision();
        detail.scale     = fd.getScale();

        // Access & DML flags
        detail.isAccessible   = fd.isAccessible();
        detail.isCreateable   = fd.isCreateable();
        detail.isUpdateable   = fd.isUpdateable();
        detail.isFilterable   = fd.isFilterable();
        detail.isSortable     = fd.isSortable();
        detail.isGroupable    = fd.isGroupable();
        detail.isNillable     = fd.isNillable();
        detail.isCaseSensitive = fd.isCaseSensitive();

        // Behavioral flags
        detail.isDefaultedOnCreate           = fd.isDefaultedOnCreate();
        detail.isDependentPicklist           = fd.isDependentPicklist();
        detail.isRestrictedPicklist          = fd.isRestrictedPicklist();
        detail.isFormulaTreatNullNumberAsZero = fd.isFormulaTreatNullNumberAsZero();

        // Extended: lookup references
        List<Schema.SObjectType> referenceTo = fd.getReferenceTo();
        if (referenceTo != null && !referenceTo.isEmpty()) {
            detail.lookupReferences = new List<String>();
            for (Schema.SObjectType ref : referenceTo) {
                detail.lookupReferences.add(ref.getDescribe().getName());
            }
        }

        // Extended: picklist values
        Schema.DisplayType fieldType = fd.getType();
        if (fieldType == Schema.DisplayType.PICKLIST || fieldType == Schema.DisplayType.MULTIPICKLIST) {
            detail.picklistValues = new List<PicklistValue>();
            for (Schema.PicklistEntry entry : fd.getPicklistValues()) {
                PicklistValue pv = new PicklistValue();
                pv.label     = entry.getLabel();
                pv.value     = entry.getValue();
                pv.isDefault = entry.isDefaultValue();
                detail.picklistValues.add(pv);
            }
        }

        return detail;
    }
}
