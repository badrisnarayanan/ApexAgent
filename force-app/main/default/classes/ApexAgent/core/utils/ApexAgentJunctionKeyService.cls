/**
 * Maintains Unique_Key__c on the ApexAgent junction objects (Topic Map,
 * Topic Tool Map, MCP Tool Map) so the same parent pair can never be mapped
 * twice. A duplicate Topic Map would put the topic and its instructions into
 * the system prompt twice; duplicate tool maps are ignored at runtime but
 * clutter the setup data.
 *
 * The unique index on Unique_Key__c is the actual guarantee (it also covers
 * two concurrent transactions). The pre-check here exists only so a
 * duplicate fails with a readable message on the offending field instead of
 * the raw DUPLICATE_VALUE error, which matters when the save comes from an
 * LLM through ApexAgentUpsertRecords.
 *
 * Call from before insert and before update. Both master-detail fields are
 * non-reparentable, so the key never changes after insert; running on update
 * as well backfills records created before the key field existed.
 */
public with sharing class ApexAgentJunctionKeyService {

    private static final String KEY_FIELD = 'Unique_Key__c';

    public static void populateUniqueKeys(List<SObject> records, SObjectField parentField, SObjectField childField) {
        String duplicateMessage = buildDuplicateMessage(parentField, childField);
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        Set<Id> recordIdsInBatch = new Set<Id>();

        for (SObject rec : records) {
            if (rec.Id != null) {
                recordIdsInBatch.add(rec.Id);
            }
            Id parentId = (Id) rec.get(parentField);
            Id childId = (Id) rec.get(childField);
            // Both lookups are required master-detail fields; if either is
            // missing the platform rejects the save after this trigger, so
            // there is no key to compute.
            if (parentId == null || childId == null) {
                continue;
            }

            String key = parentId + '_' + childId;
            rec.put(KEY_FIELD, key);
            if (recordsByKey.containsKey(key)) {
                rec.addError(childField, duplicateMessage);
            } else {
                recordsByKey.put(key, rec);
            }
        }

        if (!recordsByKey.isEmpty()) {
            rejectKeysAlreadyInUse(recordsByKey, recordIdsInBatch, records[0].getSObjectType(), childField, duplicateMessage);
        }
    }

    /**
     * Records in this same batch are excluded: their keys are being
     * recomputed right now and the in-batch check above already covers them.
     * System mode, because a duplicate is a duplicate even if it sits under a
     * parent the running user can't see.
     */
    private static void rejectKeysAlreadyInUse(
        Map<String, SObject> recordsByKey,
        Set<Id> recordIdsInBatch,
        SObjectType junctionType,
        SObjectField childField,
        String duplicateMessage
    ) {
        Set<String> keys = recordsByKey.keySet();
        // Object and field names come from describe/constants, never from input.
        String soql = 'SELECT Id, ' + KEY_FIELD + ' FROM ' + junctionType
            + ' WHERE ' + KEY_FIELD + ' IN :keys AND Id NOT IN :recordIdsInBatch';
        Map<String, Object> binds = new Map<String, Object>{
            'keys' => keys,
            'recordIdsInBatch' => recordIdsInBatch
        };

        for (SObject existing : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            SObject rec = recordsByKey.get((String) existing.get(KEY_FIELD));
            if (rec != null) {
                rec.addError(childField, duplicateMessage + ' Existing mapping: ' + existing.Id + '.');
            }
        }
    }

    private static String buildDuplicateMessage(SObjectField parentField, SObjectField childField) {
        return 'This ' + childField.getDescribe().getLabel() + ' is already mapped to this '
            + parentField.getDescribe().getLabel()
            + '. Update or activate the existing mapping instead of creating another.';
    }
}
