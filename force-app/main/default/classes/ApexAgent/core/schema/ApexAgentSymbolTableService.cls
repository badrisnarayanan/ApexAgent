/**
 * Resolves the field structure of Apex-defined types nested inside a tool's
 * Input/Output classes, via a same-org Tooling API self-callout.
 *
 * `Invocable.Action` describe() only exposes one level of fields for an
 * Apex-defined parameter — the fields of a nested wrapper class (e.g. a
 * `List<RecordInput>` parameter's own `RecordInput` fields) aren't visible
 * through it. The Tooling API's `ApexClass.SymbolTable` fills that gap, at
 * the cost of a callout — so every class needing resolution for a given
 * schema build is queried in a single bulk request, never one callout per class.
 */
public with sharing class ApexAgentSymbolTableService {

    private static final Integer CALLOUT_TIMEOUT_MS = 60000;
    private static final String TOOLING_QUERY_PATH = '/services/data/v66.0/tooling/query/?q=';

    /**
     * Bulk-resolves the SymbolTable (including Body, for generic-type recovery —
     * see resolveDeclaredType) of every given top-level Apex class name in one callout.
     *
     * @param classNames top-level Apex class names to resolve
     * @return SymbolTable + Body per class, keyed by class name
     */
    public static Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> querySymbolTables(Set<String> classNames) {
        Map<String, ApexAgentSymbolTableTypes.ApexClassRecord> byName =
            new Map<String, ApexAgentSymbolTableTypes.ApexClassRecord>();

        if (classNames == null || classNames.isEmpty()) {
            return byName;
        }

        String soql = 'SELECT Name, Body, SymbolTable FROM ApexClass WHERE Name IN (' + quotedList(classNames) + ')';
        String responseBody = executeToolingQuery(soql);

        ApexAgentSymbolTableTypes.ToolingQueryResult result =
            (ApexAgentSymbolTableTypes.ToolingQueryResult) JSON.deserialize(
                responseBody, ApexAgentSymbolTableTypes.ToolingQueryResult.class
            );

        for (ApexAgentSymbolTableTypes.ApexClassRecord rec : result.records) {
            byName.put(rec.name, rec);
        }
        return byName;
    }

    /** Finds a (possibly nested) inner class node by simple name, searching recursively. */
    public static ApexAgentSymbolTableTypes.SymbolTableNode findInnerClass(
        ApexAgentSymbolTableTypes.SymbolTableNode root,
        String innerClassName
    ) {
        if (root == null || root.innerClasses == null) {
            return null;
        }
        for (ApexAgentSymbolTableTypes.SymbolTableNode innerNode : root.innerClasses) {
            if (innerNode.name == innerClassName) {
                return innerNode;
            }
            ApexAgentSymbolTableTypes.SymbolTableNode nested = findInnerClass(innerNode, innerClassName);
            if (nested != null) {
                return nested;
            }
        }
        return null;
    }

    /**
     * Returns the full declared type text for a property (e.g. "List<FieldEntry>").
     * The Tooling API truncates generic parameters off a member field's reported
     * `type` (a `List<Foo>` field reports bare "List") — when that's detected,
     * this recovers the real text directly from the class Body using the
     * property's own line/column pointer: the source line is sliced up to the
     * field name's column, then known modifier keywords are stripped off the
     * front, leaving only the declared type. This is precise, pointer-driven
     * extraction anchored on SymbolTable's own location data — not a blind
     * regex scan of the source for field-declaration patterns.
     */
    public static String resolveDeclaredType(ApexAgentSymbolTableTypes.SymbolProperty prop, String body) {
        if (prop.type != 'List' && prop.type != 'Set') {
            return prop.type;
        }
        if (body == null || prop.location == null) {
            return prop.type;
        }

        List<String> lines = body.split('\n');
        Integer lineIdx = prop.location.line - 1;
        if (lineIdx < 0 || lineIdx >= lines.size()) {
            return prop.type;
        }

        String line = lines[lineIdx];
        Integer nameColumnIdx = prop.location.column - 1;
        if (nameColumnIdx < 0 || nameColumnIdx > line.length()) {
            return prop.type;
        }

        String prefix = line.substring(0, nameColumnIdx).trim();
        List<String> tokens = prefix.split('\\s+');
        List<String> typeTokens = new List<String>();
        for (String token : tokens) {
            if (!isModifierKeyword(token) && String.isNotBlank(token)) {
                typeTokens.add(token);
            }
        }
        return typeTokens.isEmpty() ? prop.type : String.join(typeTokens, ' ');
    }

    /**
     * Recovers a nested field's @InvocableVariable(description='...') text directly
     * from the class Body. SymbolTable's `annotations` array only confirms an
     * annotation's *name* is present (e.g. "InvocableVariable") — it never exposes
     * the annotation's own parameter values, so describe()-level label/description
     * text is unavailable for anything below the top level. This recovers it the
     * same way resolveDeclaredType() recovers a truncated generic type: anchored on
     * the property's own line pointer, not a blind scan of the source. The
     * annotation is expected on one of the few lines immediately above the field
     * declaration (matching this codebase's one-line-annotation convention) —
     * returns null rather than guessing if that shape doesn't hold.
     */
    public static String resolveDeclaredDescription(ApexAgentSymbolTableTypes.SymbolProperty prop, String body) {
        if (body == null || prop.location == null) {
            return null;
        }

        List<String> lines = body.split('\n');
        Integer fieldLineIdx = prop.location.line - 1;

        for (Integer lookback = 1; lookback <= 3; lookback++) {
            Integer annotationLineIdx = fieldLineIdx - lookback;
            if (annotationLineIdx < 0 || annotationLineIdx >= lines.size()) {
                break;
            }
            String candidate = lines[annotationLineIdx];
            if (candidate.contains('@InvocableVariable')) {
                return extractDescriptionAttribute(candidate);
            }
            if (String.isNotBlank(candidate.trim())) {
                break; // hit a non-blank, non-annotation line — annotation isn't there
            }
        }
        return null;
    }

    /** Extracts a description='...' attribute value from an annotation line, honoring \' escapes. */
    private static String extractDescriptionAttribute(String annotationLine) {
        Integer keyIdx = annotationLine.indexOf('description=');
        if (keyIdx == -1) {
            return null;
        }
        Integer quoteStart = annotationLine.indexOf('\'', keyIdx);
        if (quoteStart == -1) {
            return null;
        }

        Integer i = quoteStart + 1;
        String value = '';
        while (i < annotationLine.length()) {
            String ch = annotationLine.substring(i, i + 1);
            if (ch == '\\' && i + 1 < annotationLine.length()) {
                value += annotationLine.substring(i + 1, i + 2);
                i += 2;
                continue;
            }
            if (ch == '\'') {
                return value;
            }
            value += ch;
            i++;
        }
        return null; // unterminated — malformed annotation line, don't guess
    }

    /**
     * Splits a declared type like "List<Namespace.Foo>" into its container
     * ("List") and element type ("Namespace.Foo"). Returns null for a non-generic
     * (scalar or bare-container) type.
     */
    public static String extractGenericElementType(String declaredType) {
        if (String.isBlank(declaredType) || !declaredType.contains('<')) {
            return null;
        }
        Integer startIdx = declaredType.indexOf('<') + 1;
        Integer endIdx = declaredType.lastIndexOf('>');
        if (endIdx <= startIdx) {
            return null;
        }
        return declaredType.substring(startIdx, endIdx).trim();
    }

    // ─────────────────────────────────────────────────────────────────
    // Private: self-callout
    // ─────────────────────────────────────────────────────────────────

    // Session ID from the VF page is required here — named credentials cannot be used
    // for same-org callouts where the session must belong to the running user. Mirrors
    // the mechanism ApexAgentToolExecutor.executeViaDmlBridge() already relies on.
    @SuppressWarnings('PMD.ApexSuggestUsingNamedCredential')
    private static String executeToolingQuery(String soql) {
        String sessionId = Test.isRunningTest()
            ? 'test-session-id'
            : Page.ApexAgentSession.getContent().toString().trim();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + TOOLING_QUERY_PATH + EncodingUtil.urlEncode(soql, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + sessionId); //NOPMD - session ID from VF page required for same-org callout
        req.setTimeout(CALLOUT_TIMEOUT_MS);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new SymbolTableException(
                'Tooling API query failed (status ' + res.getStatusCode() + '): ' + res.getBody()
            );
        }
        return res.getBody();
    }

    private static String quotedList(Set<String> values) {
        List<String> quoted = new List<String>();
        for (String v : values) {
            quoted.add('\'' + String.escapeSingleQuotes(v) + '\'');
        }
        return String.join(quoted, ',');
    }

    private static Boolean isModifierKeyword(String token) {
        switch on token {
            when 'public', 'private', 'protected', 'global', 'static', 'final', 'transient', 'webservice' {
                return true;
            }
            when else {
                return false;
            }
        }
    }

    public class SymbolTableException extends Exception {}
}
