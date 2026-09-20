/**
 * Apex Action tool: resolves the Salesforce object API name for a record Id.
 */
public with sharing class GetObjectApiName {

    public class Input {
        @InvocableVariable(required=true label='Record Id' description='The Salesforce record Id to determine the object type for.')
        public String recordId;
    }

    public class Output {
        @InvocableVariable(label='Object API Name' description='API name of the object the record Id belongs to (e.g. "Account").')
        public String objectApiName;
    }

    @InvocableMethod(label='Get Object API Name' description='Resolves the object API name from a Salesforce record ID. Use this when you have a record ID but don\'t know which object it belongs to.\n\nWhen to use:\n\nYou have an unknown record ID and need to determine its object type.\nA user pastes an ID without context and you need to route to the right tool.\n\nWhen not to use:\n\nYou already know the object → skip this.')
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
        String recordIdStr = ApexAgentToolInput.requireNotBlank(inp.recordId, 'recordId');
        Id recordId;
        try {
            recordId = Id.valueOf(recordIdStr);
        } catch (Exception e) {
            throw new IllegalArgumentException('recordId is not a valid Salesforce ID: ' + recordIdStr);
        }

        Output o = new Output();
        o.objectApiName = ApexAgentUtils.getObjectApiNameFromId(recordId);
        return o;
    }
}
