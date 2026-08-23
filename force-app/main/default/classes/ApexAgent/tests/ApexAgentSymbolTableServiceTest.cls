/**
 * Verifies ApexAgentSymbolTableService's pointer-driven type/description recovery
 * degrades gracefully on malformed or out-of-range Tooling API data instead of
 * throwing, plus its inner-class lookup, generic-type parsing, and bulk callout.
 */
@IsTest
private class ApexAgentSymbolTableServiceTest {

    @IsTest
    static void testResolveDeclaredTypeRecoversGenericAndDegradesOnBadInput() {
        ApexAgentSymbolTableTypes.SymbolProperty scalarProp = buildProperty('count', 'Integer', 1, 10);
        Assert.areEqual('Integer', ApexAgentSymbolTableService.resolveDeclaredType(scalarProp, 'irrelevant body'),
            'Non-List/Set types should pass through untouched');

        String body = '        public List<FieldEntry> fields;';
        ApexAgentSymbolTableTypes.SymbolProperty listProp = buildProperty('fields', 'List', 1, 33);
        Assert.areEqual('List<FieldEntry>', ApexAgentSymbolTableService.resolveDeclaredType(listProp, body),
            'Should recover the full generic type text from the source line');

        ApexAgentSymbolTableTypes.SymbolProperty noLocationProp = buildProperty('fields', 'List', null, null);
        noLocationProp.location = null;
        Assert.areEqual('List', ApexAgentSymbolTableService.resolveDeclaredType(noLocationProp, body),
            'Should degrade to the truncated type when location is missing');

        ApexAgentSymbolTableTypes.SymbolProperty outOfBoundsProp = buildProperty('fields', 'List', 99, 1);
        Assert.areEqual('List', ApexAgentSymbolTableService.resolveDeclaredType(outOfBoundsProp, body),
            'Should degrade to the truncated type when the line pointer is out of range, not throw');
    }

    @IsTest
    static void testResolveDeclaredDescriptionFindsAnnotationAndDegradesOnBadInput() {
        String body = String.join(new List<String>{
            '    public class RecordInput {',
            '        @InvocableVariable(description=\'Field values to set on this record.\')',
            '        public List<FieldEntry> fields;',
            '',
            '',
            '        public String noAnnotation;',
            '        public String tooFarAbove;',
            '    }'
        }, '\n');

        ApexAgentSymbolTableTypes.SymbolProperty fieldsProp = buildProperty('fields', 'List', 3, 1);
        Assert.areEqual('Field values to set on this record.',
            ApexAgentSymbolTableService.resolveDeclaredDescription(fieldsProp, body),
            'Should recover the description from the annotation line directly above the field');

        ApexAgentSymbolTableTypes.SymbolProperty noAnnotationProp = buildProperty('noAnnotation', 'String', 6, 1);
        Assert.isNull(ApexAgentSymbolTableService.resolveDeclaredDescription(noAnnotationProp, body),
            'Should return null when the preceding line is not an annotation, rather than guessing');

        // Location points past the end of the (mismatched/shorter) body — must degrade to null, not throw.
        ApexAgentSymbolTableTypes.SymbolProperty outOfBoundsProp = buildProperty('ghost', 'String', 50, 1);
        Assert.isNull(ApexAgentSymbolTableService.resolveDeclaredDescription(outOfBoundsProp, body),
            'Should return null when the body is shorter than the reported location, not throw a ListException');
    }

    @IsTest
    static void testExtractGenericElementTypeAndFindInnerClass() {
        Assert.isNull(ApexAgentSymbolTableService.extractGenericElementType('String'),
            'A scalar type has no generic element');
        Assert.isNull(ApexAgentSymbolTableService.extractGenericElementType(null),
            'A null type has no generic element');
        Assert.areEqual('FieldEntry', ApexAgentSymbolTableService.extractGenericElementType('List<FieldEntry>'),
            'Should extract the element type between the angle brackets');

        ApexAgentSymbolTableTypes.SymbolTableNode nested = new ApexAgentSymbolTableTypes.SymbolTableNode();
        nested.name = 'FieldEntry';
        ApexAgentSymbolTableTypes.SymbolTableNode middle = new ApexAgentSymbolTableTypes.SymbolTableNode();
        middle.name = 'RecordInput';
        middle.innerClasses = new List<ApexAgentSymbolTableTypes.SymbolTableNode>{ nested };
        ApexAgentSymbolTableTypes.SymbolTableNode root = new ApexAgentSymbolTableTypes.SymbolTableNode();
        root.name = 'UpsertRecords';
        root.innerClasses = new List<ApexAgentSymbolTableTypes.SymbolTableNode>{ middle };

        Assert.areEqual('FieldEntry', ApexAgentSymbolTableService.findInnerClass(root, 'FieldEntry').name,
            'Should find a doubly-nested inner class by simple name');
        Assert.isNull(ApexAgentSymbolTableService.findInnerClass(root, 'NoSuchClass'),
            'Should return null for a class name not present anywhere in the tree');
        Assert.isNull(ApexAgentSymbolTableService.findInnerClass(null, 'FieldEntry'),
            'Should return null rather than throw when the root node is null');
    }

    @IsTest
    static void testQuerySymbolTablesHandlesEmptyInputAndBulkResolvesViaCallout() {
        Assert.isTrue(ApexAgentSymbolTableService.querySymbolTables(null).isEmpty(),
            'Null input should short-circuit to an empty map without a callout');
        Assert.isTrue(ApexAgentSymbolTableService.querySymbolTables(new Set<String>()).isEmpty(),
            'Empty input should short-circuit to an empty map without a callout');

        ApexAgentSymbolTableTypes.ApexClassRecord rec = new ApexAgentSymbolTableTypes.ApexClassRecord();
        rec.name = 'UpsertRecords';
        rec.body = 'public class UpsertRecords {}';
        rec.symbolTable = new ApexAgentSymbolTableTypes.SymbolTableNode();
        rec.symbolTable.name = 'UpsertRecords';
        ApexAgentSymbolTableTypes.ToolingQueryResult queryResult = new ApexAgentSymbolTableTypes.ToolingQueryResult();
        queryResult.records = new List<ApexAgentSymbolTableTypes.ApexClassRecord>{ rec };

        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(200, JSON.serialize(queryResult)));
        Test.startTest();
        Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> byName =
            ApexAgentSymbolTableService.querySymbolTables(new Set<String>{ 'UpsertRecords' });
        Test.stopTest();

        Assert.areEqual(1, byName.size(), 'Should key the bulk-resolved result by class name');
        Assert.isTrue(byName.containsKey('UpsertRecords'), 'Result map should be keyed by the resolved class name');
        Assert.areEqual('UpsertRecords', byName.get('UpsertRecords').name,
            'Should carry through the class name from the Tooling API response');
    }

    @IsTest
    static void testQuerySymbolTablesThrowsOnNonSuccessStatus() {
        Test.setMock(HttpCalloutMock.class, new ApexAgentToolingQueryMock(500, 'boom'));
        Boolean threw = false;

        Test.startTest();
        try {
            ApexAgentSymbolTableService.querySymbolTables(new Set<String>{ 'UpsertRecords' });
        } catch (ApexAgentSymbolTableService.SymbolTableException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('500'), 'Exception should carry the failing status code');
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A non-200 Tooling API response must surface as a SymbolTableException');
    }

    private static ApexAgentSymbolTableTypes.SymbolProperty buildProperty(String name, String type, Integer line, Integer column) {
        ApexAgentSymbolTableTypes.SymbolProperty prop = new ApexAgentSymbolTableTypes.SymbolProperty();
        prop.name = name;
        prop.type = type;
        if (line != null) {
            prop.location = new ApexAgentSymbolTableTypes.SymbolLocation();
            prop.location.line = line;
            prop.location.column = column;
        }
        return prop;
    }
}
