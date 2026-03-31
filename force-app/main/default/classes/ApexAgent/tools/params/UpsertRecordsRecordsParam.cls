public with sharing class UpsertRecordsRecordsParam implements ApexAgentParameterDefinition {

    public Map<String, Object> getDefinition() {
        return new Map<String, Object>{
            'type'        => 'array',
            'description' => 'List of records to upsert. Each record must have a fields array describing the field values to set.',
            'items'       => new Map<String, Object>{
                'type'                 => 'object',
                'additionalProperties' => false,
                'required'             => new List<String>{ 'fields' },
                'properties'           => new Map<String, Object>{
                    'fields' => new Map<String, Object>{
                        'type'        => 'array',
                        'description' => 'Field values to set on this record. Each entry specifies the field API name, the value, and the Apex type for conversion.',
                        'items'       => new Map<String, Object>{
                            'type'                 => 'object',
                            'additionalProperties' => false,
                            'required'             => new List<String>{ 'fieldApiName', 'value', 'apexType' },
                            'properties'           => new Map<String, Object>{
                                'fieldApiName' => new Map<String, Object>{
                                    'type'        => 'string',
                                    'description' => 'API name of the field (e.g. "Name", "Amount__c", "CloseDate")'
                                },
                                'value' => new Map<String, Object>{
                                    'oneOf'       => new List<Object>{
                                        new Map<String, Object>{ 'type' => 'string' },
                                        new Map<String, Object>{ 'type' => 'number' },
                                        new Map<String, Object>{ 'type' => 'boolean' },
                                        new Map<String, Object>{ 'type' => 'null' }
                                    },
                                    'description' => 'The value to set for this field. Use null to explicitly clear the field.'
                                },
                                'apexType' => new Map<String, Object>{
                                    'type'        => 'string',
                                    'description' => 'Apex data type used to convert the value before setting it on the record.',
                                    'enum'        => new List<String>{
                                        'String', 'Boolean', 'Integer', 'Decimal',
                                        'Date', 'DateTime', 'ID', 'Time', 'Long'
                                    }
                                }
                            }
                        }
                    }
                }
            }
        };
    }
}
