/**
 * Apex Action tool: resolves the Salesforce object API name for a record Id.
 */
public with sharing class GetObjectApiName {

    public class Input {
        @InvocableVariable(required=true label='Record Id' description='The Salesforce record Id to determine the object type for.')
        public String recordId;
    }

    public class Output {
        @InvocableVariable(label='Result' description='JSON object with the resolved objectApiName.')
        public String resultJson;
    }

    @InvocableMethod(label='Get Object API Name' description='Resolves the object API name from a Salesforce record ID. Use this when you have a record ID but don\'t know which object it belongs to.\n\nWhen to use:\n\nYou have an unknown record ID and need to determine its object type.\nA user pastes an ID without context and you need to route to the right tool.\n\nWhen not to use:\n\nYou already know the object → skip this.')
    public static List<Output> run(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(processOne(inp));
        }
        return results;
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
        o.resultJson = JSON.serialize(new Map<String, Object>{
            'objectApiName' => ApexAgentUtils.getObjectApiNameFromId(recordId)
        });
        return o;
    }
}
