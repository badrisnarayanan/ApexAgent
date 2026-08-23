/**
 * Typed wrappers for the subset of the Tooling API's `ApexClass.SymbolTable`
 * response the ApexAgent schema-reflection layer needs. `Invocable.Action`
 * describe() only exposes one level of fields for an Apex-defined input/output
 * type, so nested wrapper classes (e.g. a parameter whose type is itself an
 * inner class with its own @InvocableVariable fields) are resolved by querying
 * this structure instead. JSON.deserialize ignores any SymbolTable JSON keys
 * not modeled here (methods, constructors, interfaces, externalReferences, etc.)
 * — only class name, member field declarations, and nested inner classes matter
 * for schema generation.
 */
public class ApexAgentSymbolTableTypes {

    public class ToolingQueryResult {
        public List<ApexClassRecord> records;
    }

    public class ApexClassRecord {
        // JSON field matching is case-insensitive, so lowercase Apex names still
        // bind to the Tooling API's "Name"/"Body"/"SymbolTable" JSON keys.
        public String name;
        public String body;
        public SymbolTableNode symbolTable;
    }

    /** One class (top-level or inner) within a SymbolTable response. */
    public class SymbolTableNode {
        public String name;
        public List<SymbolProperty> properties;
        public List<SymbolTableNode> innerClasses;
    }

    /**
     * A member field declaration (Tooling API calls these "properties" regardless
     * of whether they're backed by a real Apex property or a plain public field —
     * local method variables are reported separately, under "variables", and are
     * never relevant here).
     */
    public class SymbolProperty {
        public String name;
        public String type;
        public SymbolLocation location;
    }

    /**
     * Source position of a property declaration. The Tooling API truncates
     * generic type parameters off `type` for member fields (e.g. a declared
     * `List<Foo>` field reports type "List", not "List<Foo>") — this location
     * lets ApexAgentSymbolTableService recover the full declared type text
     * directly from the class Body when that happens.
     */
    public class SymbolLocation {
        public Integer line;
        public Integer column;
    }
}
