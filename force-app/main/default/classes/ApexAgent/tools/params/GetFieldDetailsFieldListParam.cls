public with sharing class GetFieldDetailsFieldListParam implements ApexAgentParameterDefinition {

    public Map<String, Object> getDefinition() {
        return new Map<String, Object>{
            'type'        => 'array',
            'description' => 'List of field API names to retrieve details for (e.g. ["Name", "OwnerId"])',
            'items'       => new Map<String, Object>{
                'type'        => 'string',
                'description' => 'API name of the field (e.g. "Name", "OwnerId", "My_Custom_Field__c")'
            }
        };
    }
}
