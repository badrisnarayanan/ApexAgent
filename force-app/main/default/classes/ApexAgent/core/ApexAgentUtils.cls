/**
 * General-purpose utility class for the ApexAgent framework.
 * Centralises shared helper methods used across tools and services.
 */
public with sharing class ApexAgentUtils {

    /**
     * Returns the DescribeSObjectResult for the given object API name.
     * Uses Schema.describeSObjects to avoid the cost of a full GlobalDescribe.
     *
     * @param objectApiName  API name of the SObject (e.g. "Account", "My_Object__c")
     * @return               DescribeSObjectResult for the object
     * @throws IllegalArgumentException  if the API name is unknown or invalid
     */
    // describeSObjects is the only way to validate an object name without GlobalDescribe;
    // PMD's EagerlyLoadedDescribeSObjectResult is suppressed here intentionally — callers
    // only use lightweight properties (isSearchable, isAccessible, getName).
    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    public static Schema.DescribeSObjectResult getDescribe(String objectApiName) {
        try {
            return Schema.describeSObjects(new String[]{ objectApiName })[0];
        } catch (Exception e) {
            throw new IllegalArgumentException('Unknown object API name: ' + objectApiName);
        }
    }

    /**
     * Returns the object API name for the given record ID using the ID's SObjectType.
     *
     * @param recordId  A valid Salesforce record ID
     * @return          Object API name (e.g. "Account", "ApexAgent_Agent__c")
     */
    public static String getObjectApiNameFromId(Id recordId) {
        return recordId.getSObjectType().getDescribe().getName();
    }

    /**
     * Returns the API name of the name field (isNameField = true) for the given describe result.
     * Returns null if the object has no name field (rare system objects).
     *
     * @param describe  DescribeSObjectResult for the target object
     * @return          Field API name of the name field, or null
     */
    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    public static String getNameField(Schema.DescribeSObjectResult describe) {
        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            if (field.getDescribe().isNameField()) {
                return field.getDescribe().getName();
            }
        }
        return null;
    }

    /**
     * Returns the SObjectType for the given object API name.
     * Delegates to getDescribe() so callers get a consistent
     * IllegalArgumentException for unknown object names.
     *
     * @param objectApiName  API name of the SObject (e.g. "Account", "My_Object__c")
     * @return               Schema.SObjectType for the object
     * @throws IllegalArgumentException  if the API name is unknown or invalid
     */
    public static Schema.SObjectType getSObjectType(String objectApiName) {
        return getDescribe(objectApiName).getSObjectType();
    }
}
