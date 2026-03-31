public with sharing class GetObjectApiName implements ApexAgentTool {

    public Object execute(Map<String, Object> input) {
        if (input == null) {
            throw new IllegalArgumentException('Input map must not be null');
        }
        if (!input.containsKey('recordId')) {
            throw new IllegalArgumentException('Missing required input parameter: recordId');
        }
        if (input.get('recordId') == null) {
            throw new IllegalArgumentException('Input parameter recordId must not be null');
        }
        if (String.isBlank(String.valueOf(input.get('recordId')))) {
            throw new IllegalArgumentException('Input parameter recordId must not be blank');
        }

        String recordIdStr = String.valueOf(input.get('recordId')).trim();
        Id recordId;
        try {
            recordId = Id.valueOf(recordIdStr);
        } catch (Exception e) {
            throw new IllegalArgumentException('recordId is not a valid Salesforce ID: ' + recordIdStr);
        }

        return new Map<String, Object>{
            'objectApiName' => ApexAgentUtils.getObjectApiNameFromId(recordId)
        };
    }
}
