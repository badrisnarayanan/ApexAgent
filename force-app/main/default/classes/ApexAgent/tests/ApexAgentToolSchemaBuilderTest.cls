/**
 * Verifies ApexAgentToolSchemaBuilder assembles correct OpenAI-style tool
 * definitions by reflecting on real deployed tool classes: base parameter
 * schema + execution_message injection for a tool with only primitive
 * parameters, nested-object schema resolution (via a mocked Tooling API
 * callout) for a tool with an Apex-defined wrapper parameter, and graceful
 * per-class degradation when one tool class in the batch is invalid.
 */
@IsTest
private class ApexAgentToolSchemaBuilderTest {

    @IsTest
    static void testBuildToolDefinitionsHandlesNullAndEmptyInput() {
        Assert.isTrue(ApexAgentToolSchemaBuilder.buildToolDefinitions(null, false).isEmpty(),
            'A null tool map should produce no definitions');
        Assert.isTrue(ApexAgentToolSchemaBuilder.buildToolDefinitions(new Map<String, ApexAgent_Tool__c>(), false).isEmpty(),
            'An empty tool map should produce no definitions');
    }

    @IsTest
    static void testBuildToolDefinitionsForSimpleToolWithAndWithoutExecutionMessage() {
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'GetFieldDetails' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetFieldDetails')
        };

        Test.startTest();
        List<Map<String, Object>> plainDefs = ApexAgentToolSchemaBuilder.buildToolDefinitions(toolsByName, false);
        List<Map<String, Object>> withMessageDefs = ApexAgentToolSchemaBuilder.buildToolDefinitions(toolsByName, true);
        Test.stopTest();

        Assert.areEqual(1, plainDefs.size(), 'Should produce exactly one definition for the one requested tool');
        Map<String, Object> function = (Map<String, Object>) plainDefs[0].get('function');
        Assert.areEqual('GetFieldDetails', function.get('name'), 'Function name should be the Apex class name');
        Map<String, Object> parameters = (Map<String, Object>) function.get('parameters');
        Map<String, Object> properties = (Map<String, Object>) parameters.get('properties');
        Assert.isTrue(properties.containsKey('objectApiName'), 'Should expose the tool\'s declared input parameters');
        Assert.isFalse(properties.containsKey('execution_message'),
            'execution_message must not be injected when showExecutionMessage is false');

        Map<String, Object> withMessageFunction = (Map<String, Object>) withMessageDefs[0].get('function');
        Map<String, Object> withMessageParameters = (Map<String, Object>) withMessageFunction.get('parameters');
        Map<String, Object> withMessageProperties = (Map<String, Object>) withMessageParameters.get('properties');
        Assert.isTrue(withMessageProperties.containsKey('execution_message'),
            'execution_message must be injected when showExecutionMessage is true');
        List<Object> required = (List<Object>) withMessageParameters.get('required');
        Assert.isTrue(required.contains('execution_message'), 'execution_message must be marked required');
        Assert.isFalse(properties.containsKey('execution_message'),
            'Injecting execution_message into one build must not mutate the cached base definition');
    }

    @IsTest
    static void testBuildToolDefinitionsResolvesNestedApexClassParamViaSymbolTable() {
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, JSON.serialize(buildUpsertRecordsSymbolTableResponse())));

        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'UpsertRecords' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'UpsertRecords')
        };

        Test.startTest();
        List<Map<String, Object>> defs = ApexAgentToolSchemaBuilder.buildToolDefinitions(toolsByName, false);
        Test.stopTest();

        Map<String, Object> function = (Map<String, Object>) defs[0].get('function');
        Map<String, Object> parameters = (Map<String, Object>) function.get('parameters');
        Map<String, Object> properties = (Map<String, Object>) parameters.get('properties');

        Map<String, Object> recordsSchema = (Map<String, Object>) properties.get('records');
        Assert.areEqual('array', recordsSchema.get('type'), 'records is a collection parameter');
        Map<String, Object> recordItemSchema = (Map<String, Object>) recordsSchema.get('items');
        Assert.areEqual('object', recordItemSchema.get('type'), 'Each record should resolve to an object schema');

        Map<String, Object> recordProperties = (Map<String, Object>) recordItemSchema.get('properties');
        Map<String, Object> fieldsSchema = (Map<String, Object>) recordProperties.get('fields');
        Assert.areEqual('array', fieldsSchema.get('type'),
            'The nested "fields" member (List<FieldEntry>) should resolve to an array, recovering the truncated generic type');
        Assert.areEqual('Field values to set on this record.', fieldsSchema.get('description'),
            'Should recover the nested field\'s @InvocableVariable description from the class body');

        Map<String, Object> fieldEntrySchema = (Map<String, Object>) fieldsSchema.get('items');
        Map<String, Object> fieldEntryProperties = (Map<String, Object>) fieldEntrySchema.get('properties');
        Assert.isTrue(fieldEntryProperties.containsKey('fieldApiName'),
            'Should resolve two levels of nesting (RecordInput -> FieldEntry)');
    }

    @IsTest
    static void testBuildToolDefinitionsSkipsInvalidToolClassWithoutFailingBatch() {
        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'GetFieldDetails' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetFieldDetails'),
            // Real class with no @InvocableMethod — simulates a stale/typo'd Apex_Class_Name__c.
            'ApexAgentToolInput' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'ApexAgentToolInput')
        };

        Test.startTest();
        List<Map<String, Object>> defs = ApexAgentToolSchemaBuilder.buildToolDefinitions(toolsByName, false);
        Test.stopTest();

        Assert.areEqual(1, defs.size(),
            'One invalid tool class must be dropped, not fail schema-building for the whole batch');
        Map<String, Object> function = (Map<String, Object>) defs[0].get('function');
        Assert.areEqual('GetFieldDetails', function.get('name'), 'The remaining valid tool must still build correctly');
    }

    // ─────────────────────────────────────────────────────────────────
    // Fixture: a crafted SymbolTable/Body for UpsertRecords's RecordInput ->
    // FieldEntry nesting, independent of the real file's actual source text.
    // ─────────────────────────────────────────────────────────────────

    private static ApexAgentSymbolTableTypes.ToolingQueryResult buildUpsertRecordsSymbolTableResponse() {
        String body = String.join(new List<String>{
            'public class UpsertRecords {',
            '    public class RecordInput {',
            '        @InvocableVariable(description=\'Field values to set on this record.\')',
            '        public List<FieldEntry> fields;',
            '    }',
            '    public class FieldEntry {',
            '        @InvocableVariable(description=\'API name of the field.\')',
            '        public String fieldApiName;',
            '    }',
            '}'
        }, '\n');

        ApexAgentSymbolTableTypes.SymbolProperty fieldsProp = new ApexAgentSymbolTableTypes.SymbolProperty();
        fieldsProp.name = 'fields';
        fieldsProp.type = 'List';
        fieldsProp.location = new ApexAgentSymbolTableTypes.SymbolLocation();
        fieldsProp.location.line = 4;
        fieldsProp.location.column = 33;

        ApexAgentSymbolTableTypes.SymbolProperty fieldApiNameProp = new ApexAgentSymbolTableTypes.SymbolProperty();
        fieldApiNameProp.name = 'fieldApiName';
        fieldApiNameProp.type = 'String';
        fieldApiNameProp.location = new ApexAgentSymbolTableTypes.SymbolLocation();
        fieldApiNameProp.location.line = 8;
        fieldApiNameProp.location.column = 23;

        ApexAgentSymbolTableTypes.SymbolTableNode recordInputNode = new ApexAgentSymbolTableTypes.SymbolTableNode();
        recordInputNode.name = 'RecordInput';
        recordInputNode.properties = new List<ApexAgentSymbolTableTypes.SymbolProperty>{ fieldsProp };

        ApexAgentSymbolTableTypes.SymbolTableNode fieldEntryNode = new ApexAgentSymbolTableTypes.SymbolTableNode();
        fieldEntryNode.name = 'FieldEntry';
        fieldEntryNode.properties = new List<ApexAgentSymbolTableTypes.SymbolProperty>{ fieldApiNameProp };

        ApexAgentSymbolTableTypes.SymbolTableNode rootNode = new ApexAgentSymbolTableTypes.SymbolTableNode();
        rootNode.name = 'UpsertRecords';
        rootNode.innerClasses = new List<ApexAgentSymbolTableTypes.SymbolTableNode>{ recordInputNode, fieldEntryNode };

        ApexAgentSymbolTableTypes.ApexClassRecord rec = new ApexAgentSymbolTableTypes.ApexClassRecord();
        rec.name = 'UpsertRecords';
        rec.body = body;
        rec.symbolTable = rootNode;

        ApexAgentSymbolTableTypes.ToolingQueryResult result = new ApexAgentSymbolTableTypes.ToolingQueryResult();
        result.records = new List<ApexAgentSymbolTableTypes.ApexClassRecord>{ rec };
        return result;
    }
}
