/**
 * Verifies ApexAgentToolSchemaBuilder's two responsibilities:
 *  - buildDefinitions(): reflects on real deployed tool classes to produce the
 *    definition ApexAgentToolSchemaRegenQueueable persists to Schema__c —
 *    base parameter schema, nested-object schema resolution (via a mocked
 *    Tooling API callout), and graceful per-class degradation when one class
 *    in the batch is invalid.
 *  - buildToolDefinitionsFromSchema(): the live per-turn path, which only ever
 *    reads each tool's precomputed Schema__c — execution_message injection,
 *    and skipping (never failing the turn for) a tool with a blank or corrupt
 *    stored schema.
 */
@IsTest
private class ApexAgentToolSchemaBuilderTest {

    @IsTest
    static void testBuildDefinitionsReflectsRealToolClassesAndDropsInvalidOnes() {
        Test.startTest();
        Map<String, Map<String, Object>> emptyResult = ApexAgentToolSchemaBuilder.buildDefinitions(new Set<String>());
        Map<String, Map<String, Object>> defsByClass = ApexAgentToolSchemaBuilder.buildDefinitions(new Set<String>{
            'GetFieldDetails',
            // Real class with no @InvocableMethod — simulates a stale/typo'd Apex_Class_Name__c.
            'ApexAgentToolInput'
        });
        Test.stopTest();

        Assert.isTrue(emptyResult.isEmpty(), 'An empty class name set should produce no definitions');
        Assert.areEqual(1, defsByClass.size(),
            'One invalid tool class must be dropped, not fail schema-building for the whole batch');

        Map<String, Object> def = defsByClass.get('GetFieldDetails');
        Assert.isNotNull(def, 'The remaining valid tool must still build correctly');
        Map<String, Object> function = (Map<String, Object>) def.get('function');
        Assert.areEqual('GetFieldDetails', function.get('name'), 'Function name should be the Apex class name');
        Map<String, Object> parameters = (Map<String, Object>) function.get('parameters');
        Map<String, Object> properties = (Map<String, Object>) parameters.get('properties');
        Assert.isTrue(properties.containsKey('objectApiName'), 'Should expose the tool\'s declared input parameters');
        Assert.isFalse(properties.containsKey('execution_message'),
            'execution_message is a per-turn addition, never part of the persisted base definition');
    }

    @IsTest
    static void testBuildDefinitionsResolvesNestedApexClassParamViaSymbolTable() {
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, JSON.serialize(buildUpsertRecordsSymbolTableResponse())));

        Test.startTest();
        Map<String, Map<String, Object>> defsByClass =
            ApexAgentToolSchemaBuilder.buildDefinitions(new Set<String>{ 'UpsertRecords' });
        Test.stopTest();

        Map<String, Object> function = (Map<String, Object>) defsByClass.get('UpsertRecords').get('function');
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
    static void testBuildToolDefinitionsFromSchemaInjectsExecutionMessageAndSkipsBadSchema() {
        String storedSchema = JSON.serialize(new Map<String, Object>{
            'type' => 'function',
            'function' => new Map<String, Object>{
                'name' => 'GetFieldDetails',
                'description' => 'Looks up field metadata.',
                'parameters' => new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{
                        'objectApiName' => new Map<String, Object>{ 'type' => 'string' }
                    },
                    'additionalProperties' => false
                }
            }
        });

        Map<String, ApexAgent_Tool__c> toolsByName = new Map<String, ApexAgent_Tool__c>{
            'GetFieldDetails' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'GetFieldDetails', Schema__c = storedSchema),
            // Never generated (e.g. Apex class invalid) — must be skipped, not fail the turn.
            'NeverGenerated' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'NeverGenerated', Schema__c = null),
            // Corrupted stored value — must also be skipped, not throw.
            'Corrupt' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'Corrupt', Schema__c = '{not json')
        };

        Assert.isTrue(ApexAgentToolSchemaBuilder.buildToolDefinitionsFromSchema(null, false).isEmpty(),
            'A null tool map should produce no definitions');
        Assert.isTrue(ApexAgentToolSchemaBuilder.buildToolDefinitionsFromSchema(new Map<String, ApexAgent_Tool__c>(), false).isEmpty(),
            'An empty tool map should produce no definitions');

        List<Map<String, Object>> plainDefs = ApexAgentToolSchemaBuilder.buildToolDefinitionsFromSchema(toolsByName, false);
        List<Map<String, Object>> withMessageDefs = ApexAgentToolSchemaBuilder.buildToolDefinitionsFromSchema(toolsByName, true);

        Assert.areEqual(1, plainDefs.size(),
            'The blank and corrupt stored schemas must be skipped, leaving only the one good definition');
        Map<String, Object> function = (Map<String, Object>) plainDefs[0].get('function');
        Map<String, Object> parameters = (Map<String, Object>) function.get('parameters');
        Map<String, Object> properties = (Map<String, Object>) parameters.get('properties');
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
            'Injecting execution_message into one build must not leak into a separately parsed build');
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
