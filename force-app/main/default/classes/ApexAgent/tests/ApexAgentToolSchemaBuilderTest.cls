/**
 * Verifies ApexAgentToolSchemaBuilder's two responsibilities:
 *  - buildDefinitions(): reflects on real deployed tool classes to produce the
 *    chat and MCP definitions ApexAgentToolSchemaRegenQueueable persists to
 *    Schema__c and MCP_Schema__c — base parameter schema, output schema (incl.
 *    SObject outputs), nested-object schema resolution (via a mocked Tooling
 *    API callout), and graceful per-class degradation when one class in the
 *    batch is invalid.
 *  - buildToolDefinitionsFromSchema(): the live per-turn path, which only ever
 *    reads each tool's precomputed Schema__c — execution_message injection,
 *    and skipping (never failing the turn for) a tool with a blank or corrupt
 *    stored schema.
 */
@IsTest
private class ApexAgentToolSchemaBuilderTest {

    @IsTest
    static void testBuildDefinitionsReflectsRealToolClassesAndDropsInvalidOnes() {
        // ApexAgentGetFieldDetails/ApexAgentGetRecordDetails output nested Apex classes, so their
        // symbol tables are queried; an empty result leaves those classes unresolved.
        ApexAgentSymbolTableTypes.ToolingQueryResult noSymbolTables = new ApexAgentSymbolTableTypes.ToolingQueryResult();
        noSymbolTables.records = new List<ApexAgentSymbolTableTypes.ApexClassRecord>();
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, JSON.serialize(noSymbolTables)));

        Test.startTest();
        Map<String, ApexAgentToolSchemaBuilder.ToolDefinitions> emptyResult =
            ApexAgentToolSchemaBuilder.buildDefinitions(new Set<String>());
        Map<String, ApexAgentToolSchemaBuilder.ToolDefinitions> defsByClass = ApexAgentToolSchemaBuilder.buildDefinitions(new Set<String>{
            'ApexAgentGetFieldDetails',
            'ApexAgentGetRecordDetails',
            // Real class with no @InvocableMethod — simulates a stale/typo'd Apex_Class_Name__c.
            'ApexAgentToolInput'
        });
        Test.stopTest();

        Assert.isTrue(emptyResult.isEmpty(), 'An empty class name set should produce no definitions');
        Assert.areEqual(2, defsByClass.size(),
            'One invalid tool class must be dropped, not fail schema-building for the whole batch');

        ApexAgentToolSchemaBuilder.ToolDefinitions defs = defsByClass.get('ApexAgentGetFieldDetails');
        Assert.isNotNull(defs, 'The remaining valid tool must still build correctly');
        Map<String, Object> function = (Map<String, Object>) defs.chat.get('function');
        Assert.areEqual('ApexAgentGetFieldDetails', function.get('name'), 'Function name should be the Apex class name');
        Map<String, Object> parameters = (Map<String, Object>) function.get('parameters');
        Map<String, Object> properties = (Map<String, Object>) parameters.get('properties');
        Assert.isTrue(properties.containsKey('objectApiName'), 'Should expose the tool\'s declared input parameters');
        Assert.isFalse(properties.containsKey('execution_message'),
            'execution_message is a per-turn addition, never part of the persisted base definition');

        Map<String, Object> mcp = defs.mcp;
        Assert.areEqual('ApexAgentGetFieldDetails', mcp.get('name'), 'The MCP definition should carry the same tool name');
        Assert.areEqual('Get Field Details', mcp.get('title'), 'The MCP title should come from the action label');
        Assert.areEqual(function.get('description'), mcp.get('description'), 'Both shapes share one description');
        Assert.areEqual(parameters, mcp.get('inputSchema'), 'The MCP inputSchema is the same schema as the chat parameters');
        Map<String, Object> outputSchema = (Map<String, Object>) mcp.get('outputSchema');
        Assert.areEqual('object', outputSchema.get('type'), 'outputSchema must be an object schema');
        Assert.isFalse(outputSchema.containsKey('required'),
            'Output fields are never required — the executor drops null outputs');
        Map<String, Object> outputProperties = (Map<String, Object>) outputSchema.get('properties');
        Assert.areEqual('boolean', ((Map<String, Object>) outputProperties.get('isAccessible')).get('type'),
            'A Boolean output should map to boolean');
        Assert.isNotNull(((Map<String, Object>) outputProperties.get('message')).get('description'),
            'Output descriptions should carry over from @InvocableVariable');
        Assert.areEqual('array', ((Map<String, Object>) outputProperties.get('fields')).get('type'),
            'A List output of an Apex class should map to an array even when the class can\'t be resolved');

        Map<String, Object> recordOutput = (Map<String, Object>) ((Map<String, Object>)
            ((Map<String, Object>) defsByClass.get('ApexAgentGetRecordDetails').mcp.get('outputSchema')).get('properties')).get('record');
        Assert.areEqual('object', recordOutput.get('type'), 'An SObject output should map to a free-form object, not a string');
    }

    @IsTest
    static void testBuildDefinitionsResolvesNestedApexClassParamViaSymbolTable() {
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, JSON.serialize(buildUpsertRecordsSymbolTableResponse())));

        Test.startTest();
        Map<String, ApexAgentToolSchemaBuilder.ToolDefinitions> defsByClass =
            ApexAgentToolSchemaBuilder.buildDefinitions(new Set<String>{ 'ApexAgentUpsertRecords' });
        Test.stopTest();

        Map<String, Object> function = (Map<String, Object>) defsByClass.get('ApexAgentUpsertRecords').chat.get('function');
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

        Assert.isFalse(JSON.serialize(defsByClass.get('ApexAgentUpsertRecords').mcp.get('outputSchema')).contains('additionalProperties'),
            'Nested output objects must not be strict, since a client validates structuredContent against them');
        Assert.isTrue(JSON.serialize(defsByClass.get('ApexAgentUpsertRecords').mcp.get('inputSchema')).contains('additionalProperties'),
            'The input schema keeps additionalProperties:false');

        Map<String, Object> outputProperties = (Map<String, Object>)
            ((Map<String, Object>) defsByClass.get('ApexAgentUpsertRecords').mcp.get('outputSchema')).get('properties');
        Assert.isTrue(outputProperties.containsKey('success') && outputProperties.containsKey('results'),
            'Output classes should be included in the symbol-table lookup and reflected into outputSchema');
        Assert.areEqual('array', ((Map<String, Object>) outputProperties.get('results')).get('type'),
            'A List output of a nested Apex class should map to an array');
    }

    @IsTest
    static void testBuildToolDefinitionsFromSchemaInjectsExecutionMessageAndSkipsBadSchema() {
        String storedSchema = JSON.serialize(new Map<String, Object>{
            'type' => 'function',
            'function' => new Map<String, Object>{
                'name' => 'ApexAgentGetFieldDetails',
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
            'ApexAgentGetFieldDetails' => new ApexAgent_Tool__c(Apex_Class_Name__c = 'ApexAgentGetFieldDetails', Schema__c = storedSchema),
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
    // Fixture: a crafted SymbolTable/Body for ApexAgentUpsertRecords's RecordInput ->
    // FieldEntry nesting, independent of the real file's actual source text.
    // ─────────────────────────────────────────────────────────────────

    private static ApexAgentSymbolTableTypes.ToolingQueryResult buildUpsertRecordsSymbolTableResponse() {
        String body = String.join(new List<String>{
            'public class ApexAgentUpsertRecords {',
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
        rootNode.name = 'ApexAgentUpsertRecords';
        rootNode.innerClasses = new List<ApexAgentSymbolTableTypes.SymbolTableNode>{ recordInputNode, fieldEntryNode };

        ApexAgentSymbolTableTypes.ApexClassRecord rec = new ApexAgentSymbolTableTypes.ApexClassRecord();
        rec.name = 'ApexAgentUpsertRecords';
        rec.body = body;
        rec.symbolTable = rootNode;

        ApexAgentSymbolTableTypes.ToolingQueryResult result = new ApexAgentSymbolTableTypes.ToolingQueryResult();
        result.records = new List<ApexAgentSymbolTableTypes.ApexClassRecord>{ rec };
        return result;
    }
}
