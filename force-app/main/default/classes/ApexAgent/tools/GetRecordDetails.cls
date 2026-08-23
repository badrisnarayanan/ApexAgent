/**
 * Apex Action tool: fetches accessible field values for records by Id.
 *
 * Bulk-safe: every input's Id/object type is resolved first (no SOQL), inputs
 * are grouped by object type, and each group is fetched with a single query
 * covering all its Ids — never one query per input inside the loop.
 */
@SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
public with sharing class GetRecordDetails {

    public class Input {
        @InvocableVariable(required=true label='Record Id' description='The Salesforce record Id to fetch details for.')
        public String recordId;
    }

    public class Output {
        @InvocableVariable(label='Result' description='JSON object with the record\'s accessible field values.')
        public String resultJson;
    }

    private class ResolvedRequest {
        Input source;
        Id recordId;
        String objectApiName;
        Map<String, Object> earlyResult; // set when resolution itself already determined the outcome
    }

    @InvocableMethod(label='Get Record Details' description='Returns all accessible fields and its values for a single record given its Salesforce ID. Skips long text areas and rich text fields, and enriches lookup fields with their related record\'s name.\n\nWhen to use:\n\nYou have an exact record ID and need to inspect its data.\nUser asks "what\'s on this record?" or "show me the details for [ID]".\nYou need to verify field values before performing an update or upsert.\n\nWhen not to use:\n\nYou need to find records by criteria → use QueryRecords or SearchRecords.\nYou don\'t have the record ID → use SearchRecords first.\nYou need to query multiple records → use QueryRecords.\nYou need data from long text area rich text fiels -> use QueryRecords.')
    public static List<Output> run(List<Input> inputs) {
        List<ResolvedRequest> resolved = new List<ResolvedRequest>();
        for (Input inp : inputs) {
            resolved.add(resolveRequest(inp));
        }

        Map<Id, SObject> recordsById = fetchAllGroupedByObjectType(resolved);

        List<Output> results = new List<Output>();
        for (ResolvedRequest r : resolved) {
            results.add(buildOutput(r, recordsById));
        }
        return results;
    }

    // ─── Phase 1: resolve object type + parse Id (no SOQL) ───────────────────────

    private static ResolvedRequest resolveRequest(Input inp) {
        ResolvedRequest r = new ResolvedRequest();
        r.source = inp;

        String recordIdStr = ApexAgentToolInput.requireNotBlank(inp.recordId, 'recordId');
        try {
            r.recordId = Id.valueOf(recordIdStr);
        } catch (Exception e) {
            throw new IllegalArgumentException('recordId is not a valid Salesforce ID: ' + recordIdStr);
        }

        r.objectApiName = ApexAgentUtils.getObjectApiNameFromId(r.recordId);
        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(r.objectApiName);
        if (!describe.isAccessible()) {
            r.earlyResult = new Map<String, Object>{
                'isAccessible' => false,
                'message'      => 'Object ' + r.objectApiName + ' is not accessible by the running user'
            };
        }
        return r;
    }

    // ─── Phase 2: one bulk query per distinct object type ────────────────────────

    private static Map<Id, SObject> fetchAllGroupedByObjectType(List<ResolvedRequest> resolved) {
        Map<String, Set<Id>> idsByObjectType = new Map<String, Set<Id>>();
        for (ResolvedRequest r : resolved) {
            if (r.earlyResult != null) {
                continue;
            }
            if (!idsByObjectType.containsKey(r.objectApiName)) {
                idsByObjectType.put(r.objectApiName, new Set<Id>());
            }
            idsByObjectType.get(r.objectApiName).add(r.recordId);
        }

        Map<Id, SObject> recordsById = new Map<Id, SObject>();
        for (String objectApiName : idsByObjectType.keySet()) {
            Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);
            List<String> queryFields = buildFieldList(describe);
            Set<Id> ids = idsByObjectType.get(objectApiName);

            String soql = 'SELECT ' + String.join(queryFields, ', ')
                        + ' FROM '  + objectApiName
                        + ' WHERE Id IN :ids';

            for (SObject record : Database.queryWithBinds(
                soql, new Map<String, Object>{ 'ids' => ids }, AccessLevel.USER_MODE
            )) {
                recordsById.put(record.Id, record);
            }
        }
        return recordsById;
    }

    // ─── Phase 3: assemble one Output per Input, in original order ──────────────

    private static Output buildOutput(ResolvedRequest r, Map<Id, SObject> recordsById) {
        Output o = new Output();

        if (r.earlyResult != null) {
            o.resultJson = JSON.serialize(r.earlyResult);
            return o;
        }

        SObject record = recordsById.get(r.recordId);
        if (record == null) {
            o.resultJson = JSON.serialize(new Map<String, Object>{
                'found'   => false,
                'message' => 'No record found for Id: ' + r.recordId
            });
            return o;
        }

        o.resultJson = JSON.serialize(record);
        return o;
    }

    // ─── Field list builder ──────────────────────────────────────────────────────

    private static List<String> buildFieldList(Schema.DescribeSObjectResult describe) {
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
