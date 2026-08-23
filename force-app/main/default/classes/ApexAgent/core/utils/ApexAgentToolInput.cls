/**
 * Shared input-validation helper for ApexAgent tool Apex Actions. Top-level required
 * parameters are validated generically by ApexAgentToolExecutor (against @InvocableVariable
 * required=true, which the platform itself does not enforce at invoke time) before a
 * tool's @InvocableMethod is even called — but that check only confirms a value was
 * supplied, not that a string is non-blank. This covers that remaining validation, for
 * top-level and nested fields alike, so errors surfaced to the LLM stay consistently worded.
 */
public with sharing class ApexAgentToolInput {

    /** Validates a required top-level or nested String field is present and non-blank. */
    public static String requireNotBlank(String value, String paramName) {
        if (String.isBlank(value)) {
            throw new IllegalArgumentException('Input parameter ' + paramName + ' must not be blank');
        }
        return value.trim();
    }
}
