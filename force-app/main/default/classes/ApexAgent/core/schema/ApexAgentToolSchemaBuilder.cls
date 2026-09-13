/**
 * Builds OpenAI-style function-calling tool definitions by reflecting on each
 * tool's Apex Action (`@InvocableMethod`), and separately assembles the live
 * per-turn tool array the agent loop sends to the LLM.
 *
 * The reflection side (buildDefinitions) is the expensive part — one Tooling API
 * callout for nested Apex-defined parameter types — and only ever runs from
 * ApexAgentToolSchemaRegenQueueable, which persists its result onto each
 * ApexAgent_Tool__c.Schema__c. The agent loop never reflects live: it reads
 * Schema__c and only adds the per-turn execution_message parameter
 * (buildToolDefinitionsFromSchema).
 *
 * For each tool:
 *  - `Invocable.Action.createCustomAction('apex', className).getDescribe()` supplies
 *    the action's label/description and its top-level input/output parameters
 *    (name, type, required, description, collection-ness via maxOccurs, and — for an
 *    Apex-defined parameter type — the referenced class via apexClass).
 *  - describe() only exposes one level of fields for an Apex-defined parameter type,
 *    so a parameter that is itself a wrapper class (e.g. a list of record objects)
 *    is resolved via ApexAgentSymbolTableService, which is queried once in bulk for
 *    every tool class that needs it — never per parameter or per tool.
 *  - The Output class's fields are folded into the function's description text
 *    (there is no standard "output schema" slot in OpenAI's tool-calling spec) so
 *    the model still learns the result shape before calling the tool.
 */
public with sharing class ApexAgentToolSchemaBuilder {

    private static final String ACTION_TYPE = 'apex';
    private static final Integer MAX_NESTING_DEPTH = 5;

    private static final Set<String> KNOWN_APEX_PRIMITIVES = new Set<String>{
        'String', 'Boolean', 'Integer', 'Decimal', 'Double', 'Long', 'Date', 'Datetime', 'Time', 'Id', 'Blob'
    };

    /**
     * Builds the per-turn function-calling tool definitions array for every tool
     * in toolsByName (keyed by Apex_Class_Name__c) by reading each tool's
     * precomputed Schema__c — never by reflecting on the Apex class live. A tool
     * whose Schema__c is blank (never generated, or last generation attempt
     * failed) or holds corrupt JSON is skipped rather than failing the whole turn.
     * When showExecutionMessage is true, an execution_message parameter is
     * injected into every tool's schema so the LLM can provide a user-friendly
     * status description.
     *
     * @param toolsByName tools to build definitions for, keyed by Apex class name
     * @param showExecutionMessage whether to inject the synthetic execution_message param
     * @return one OpenAI-style {type:'function', function:{...}} map per tool
     */
    public static List<Map<String, Object>> buildToolDefinitionsFromSchema(
        Map<String, ApexAgent_Tool__c> toolsByName,
        Boolean showExecutionMessage
    ) {
        List<Map<String, Object>> defs = new List<Map<String, Object>>();
        if (toolsByName == null || toolsByName.isEmpty()) {
            return defs;
        }

        for (String className : toolsByName.keySet()) {
            Map<String, Object> def = buildSingleToolDefinitionFromSchema(
                className, toolsByName.get(className).Schema__c, showExecutionMessage == true
            );
            if (def != null) {
                defs.add(def);
            }
        }
        return defs;
    }

    /**
     * Parsing and execution_message injection are wrapped in one try/catch —
     * Schema__c is directly editable (an admin can hand-edit or paste into it),
     * so a value that's syntactically valid JSON but structurally incomplete
     * (e.g. missing the expected function/parameters/properties shape) must be
     * skipped here too, not just a hard JSON parse failure, or one bad tool's
     * NullPointerException inside applyExecutionMessage would fail the whole turn.
     */
    private static Map<String, Object> buildSingleToolDefinitionFromSchema(
        String className, String schemaJson, Boolean showExecutionMessage
    ) {
        if (String.isBlank(schemaJson)) {
            System.debug(LoggingLevel.WARN, 'Skipping tool class (schema not yet generated): ' + className);
            return null;
        }
        try {
            Map<String, Object> baseDef = (Map<String, Object>) JSON.deserializeUntyped(schemaJson);
            return applyExecutionMessage(baseDef, showExecutionMessage);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Skipping tool class (invalid stored schema): ' + className + ' — ' + e.getMessage());
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Fresh definition building (describe + symbol table) — called only from
    // ApexAgentToolSchemaRegenQueueable to (re)populate Schema__c.
    // ─────────────────────────────────────────────────────────────────

    public static Map<String, Map<String, Object>> buildDefinitions(Set<String> classNames) {
        Map<String, Invocable.Action.DescribeResult> describeByClass = describeAll(classNames);
        Set<String> classesNeedingSymbolTable = collectClassesNeedingSymbolTable(describeByClass);
        Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> symbolTables =
            classesNeedingSymbolTable.isEmpty()
                ? new Map<String, ApexAgentSymbolTableTypes.ApexClassRecord>()
                : ApexAgentSymbolTableService.querySymbolTables(classesNeedingSymbolTable);

        Map<String, Map<String, Object>> result = new Map<String, Map<String, Object>>();
        for (String className : describeByClass.keySet()) {
            result.put(className, buildSingleDefinition(className, describeByClass.get(className), symbolTables));
        }
        return result;
    }

    /**
     * Describes each tool class individually so one stale/typo'd Apex_Class_Name__c
     * only drops that tool from the schema instead of failing the whole batch — the
     * rest of the agent's tools must stay usable for the turn.
     */
    private static Map<String, Invocable.Action.DescribeResult> describeAll(Set<String> classNames) {
        Map<String, Invocable.Action.DescribeResult> byClass = new Map<String, Invocable.Action.DescribeResult>();
        for (String className : classNames) {
            List<Invocable.Action.DescribeResult> describes;
            try {
                describes = Invocable.Action.createCustomAction(ACTION_TYPE, className).getDescribe();
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Skipping tool class (Apex Action describe failed): ' + className + ' — ' + e.getMessage());
                continue;
            }
            if (describes.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'Skipping tool class (not found or has no @InvocableMethod): ' + className);
                continue;
            }
            byClass.put(className, describes[0]);
        }
        return byClass;
    }

    private static Set<String> collectClassesNeedingSymbolTable(Map<String, Invocable.Action.DescribeResult> describeByClass) {
        Set<String> topLevelNames = new Set<String>();
        for (String className : describeByClass.keySet()) {
            Invocable.Action.DescribeResult d = describeByClass.get(className);
            for (Invocable.Action.InputParameter ip : d.getInputs()) {
                if (String.isNotBlank(ip.getApexClass())) {
                    topLevelNames.add(topLevelClassOf(ip.getApexClass()));
                }
            }
            for (Invocable.Action.OutputParameter op : d.getOutputs()) {
                if (String.isNotBlank(op.getApexClass())) {
                    topLevelNames.add(topLevelClassOf(op.getApexClass()));
                }
            }
        }
        return topLevelNames;
    }

    private static Map<String, Object> buildSingleDefinition(
        String className,
        Invocable.Action.DescribeResult describe,
        Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> symbolTables
    ) {
        Map<String, Object> properties = new Map<String, Object>();
        List<String> required = new List<String>();

        for (Invocable.Action.InputParameter ip : describe.getInputs()) {
            properties.put(ip.getName(), buildParameterSchema(
                ip.getType(), ip.getApexClass(), ip.getMaxOccurs(), ip.getDescription(), symbolTables, 0
            ));
            if (ip.getRequired() == true) {
                required.add(ip.getName());
            }
        }

        Map<String, Object> parameters = new Map<String, Object>{ 'type' => 'object', 'properties' => properties };
        if (!required.isEmpty()) {
            parameters.put('required', required);
        }
        parameters.put('additionalProperties', false);

        return new Map<String, Object>{
            'type' => 'function',
            'function' => new Map<String, Object>{
                'name'        => className,
                'description' => buildDescriptionWithOutputSummary(describe),
                'parameters'  => parameters
            }
        };
    }

    // ─────────────────────────────────────────────────────────────────
    // Parameter / nested-object schema construction
    // ─────────────────────────────────────────────────────────────────

    private static Map<String, Object> buildParameterSchema(
        String primitiveType,
        String apexClass,
        Integer maxOccurs,
        String description,
        Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> symbolTables,
        Integer depth
    ) {
        Boolean isCollection = maxOccurs != null && maxOccurs > 1;
        Map<String, Object> itemSchema = String.isNotBlank(apexClass)
            ? buildObjectSchema(apexClass, symbolTables, depth)
            : new Map<String, Object>{ 'type' => mapDescribeTypeToJsonType(primitiveType) };

        if (isCollection) {
            Map<String, Object> arraySchema = new Map<String, Object>{ 'type' => 'array', 'items' => itemSchema };
            if (String.isNotBlank(description)) {
                arraySchema.put('description', description);
            }
            return arraySchema;
        }

        if (String.isNotBlank(description)) {
            itemSchema.put('description', description);
        }
        return itemSchema;
    }

    private static Map<String, Object> buildObjectSchema(
        String apexClass,
        Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> symbolTables,
        Integer depth
    ) {
        if (depth >= MAX_NESTING_DEPTH) {
            return new Map<String, Object>{ 'type' => 'object' };
        }

        String topLevelName = topLevelClassOf(apexClass);
        String leafName = leafClassOf(apexClass);
        ApexAgentSymbolTableTypes.ApexClassRecord rec = symbolTables.get(topLevelName);
        if (rec == null) {
            return new Map<String, Object>{ 'type' => 'object' };
        }

        ApexAgentSymbolTableTypes.SymbolTableNode node =
            ApexAgentSymbolTableService.findInnerClass(rec.symbolTable, leafName);
        if (node == null || node.properties == null) {
            return new Map<String, Object>{ 'type' => 'object' };
        }

        Map<String, Object> properties = new Map<String, Object>();
        for (ApexAgentSymbolTableTypes.SymbolProperty prop : node.properties) {
            properties.put(prop.name, buildNestedFieldSchema(prop, rec, topLevelName, symbolTables, depth + 1));
        }

        return new Map<String, Object>{
            'type' => 'object',
            'properties' => properties,
            'additionalProperties' => false
        };
    }

    private static Map<String, Object> buildNestedFieldSchema(
        ApexAgentSymbolTableTypes.SymbolProperty prop,
        ApexAgentSymbolTableTypes.ApexClassRecord rec,
        String topLevelName,
        Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> symbolTables,
        Integer depth
    ) {
        String declaredType = ApexAgentSymbolTableService.resolveDeclaredType(prop, rec.body);
        String elementType = ApexAgentSymbolTableService.extractGenericElementType(declaredType);
        String description = ApexAgentSymbolTableService.resolveDeclaredDescription(prop, rec.body);

        if (elementType != null) {
            Map<String, Object> items = KNOWN_APEX_PRIMITIVES.contains(simpleName(elementType))
                ? new Map<String, Object>{ 'type' => mapApexTypeToJsonType(simpleName(elementType)) }
                : buildObjectSchema(topLevelName + '$' + simpleName(elementType), symbolTables, depth);
            Map<String, Object> arraySchema = new Map<String, Object>{ 'type' => 'array', 'items' => items };
            if (String.isNotBlank(description)) {
                arraySchema.put('description', description);
            }
            return arraySchema;
        }

        Map<String, Object> fieldSchema = KNOWN_APEX_PRIMITIVES.contains(simpleName(declaredType))
            ? new Map<String, Object>{ 'type' => mapApexTypeToJsonType(simpleName(declaredType)) }
            : buildObjectSchema(topLevelName + '$' + simpleName(declaredType), symbolTables, depth);
        if (String.isNotBlank(description)) {
            fieldSchema.put('description', description);
        }
        return fieldSchema;
    }

    // ─────────────────────────────────────────────────────────────────
    // Output summary folded into the description (decision: no separate output schema key)
    // ─────────────────────────────────────────────────────────────────

    private static String buildDescriptionWithOutputSummary(Invocable.Action.DescribeResult describe) {
        String baseDescription = describe.getDescription();
        List<String> outputLines = new List<String>();
        for (Invocable.Action.OutputParameter op : describe.getOutputs()) {
            String typeLabel = String.isNotBlank(op.getApexClass()) ? 'object' : mapDescribeTypeToJsonType(op.getType());
            String line = op.getName() + ' (' + typeLabel + ')';
            if (String.isNotBlank(op.getDescription())) {
                line += ' — ' + op.getDescription();
            }
            outputLines.add(line);
        }

        if (outputLines.isEmpty()) {
            return baseDescription;
        }
        return baseDescription + '\n\nReturns: ' + String.join(outputLines, '; ');
    }

    // ─────────────────────────────────────────────────────────────────
    // execution_message injection
    // ─────────────────────────────────────────────────────────────────

    /**
     * baseDef is freshly deserialized per call (see parseStoredSchema) and never
     * shared across turns or tools, so it's safe to mutate in place here.
     */
    private static Map<String, Object> applyExecutionMessage(Map<String, Object> baseDef, Boolean showExecutionMessage) {
        if (!showExecutionMessage) {
            return baseDef;
        }

        Map<String, Object> function = (Map<String, Object>) baseDef.get('function');
        Map<String, Object> parameters = (Map<String, Object>) function.get('parameters');
        Map<String, Object> properties = (Map<String, Object>) parameters.get('properties');

        properties.put('execution_message', new Map<String, Object>{
            'type'        => 'string',
            'description' => 'Brief, user-friendly description of what you are doing '
                + 'with this specific tool call, in present continuous tense '
                + '(e.g. \'Searching for account records\'). '
                + 'Under 60 characters. Do not end with ellipsis.'
        });

        List<Object> required = parameters.containsKey('required')
            ? (List<Object>) parameters.get('required')
            : new List<Object>();
        required.add('execution_message');
        parameters.put('required', required);

        return baseDef;
    }

    // ─────────────────────────────────────────────────────────────────
    // Type-name helpers
    // ─────────────────────────────────────────────────────────────────

    /** apexClass is reported as "TopLevelClass$Inner$Nested" — everything before the first '$'. */
    private static String topLevelClassOf(String apexClass) {
        Integer idx = apexClass.indexOf('$');
        return idx == -1 ? apexClass : apexClass.substring(0, idx);
    }

    /** The simple name of the innermost class in an apexClass path. */
    private static String leafClassOf(String apexClass) {
        Integer idx = apexClass.lastIndexOf('$');
        return idx == -1 ? apexClass : apexClass.substring(idx + 1);
    }

    /** Strips a namespace/outer-class qualifier (e.g. "Outer.Inner" -> "Inner") from a type name. */
    private static String simpleName(String typeName) {
        Integer idx = typeName.lastIndexOf('.');
        return idx == -1 ? typeName : typeName.substring(idx + 1);
    }

    private static String mapDescribeTypeToJsonType(String describeType) {
        if (String.isBlank(describeType)) {
            return 'string';
        }
        switch on describeType.toUpperCase() {
            when 'BOOLEAN' {
                return 'boolean';
            }
            when 'INTEGER', 'DOUBLE', 'DECIMAL', 'CURRENCY', 'PERCENT', 'LONG' {
                return 'number';
            }
            when else {
                return 'string';
            }
        }
    }

    private static String mapApexTypeToJsonType(String apexTypeName) {
        switch on apexTypeName {
            when 'Boolean' {
                return 'boolean';
            }
            when 'Integer', 'Decimal', 'Double', 'Long' {
                return 'number';
            }
            when else {
                return 'string';
            }
        }
    }
}
