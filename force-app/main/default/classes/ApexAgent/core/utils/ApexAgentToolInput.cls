/**
 * Shared input-validation helpers for ApexAgentTool implementations. Centralizes the
 * containsKey/null/blank/type-check ladder that every tool previously hand-rolled, so
 * validation errors surfaced to the LLM are consistently worded and every parameter
 * cast is type-checked before use (an unchecked cast on an LLM-supplied argument of
 * the wrong JSON type throws a cryptic TypeException instead of a recoverable,
 * well-worded IllegalArgumentException).
 */
public with sharing class ApexAgentToolInput {

    public static void requireMap(Map<String, Object> input) {
        if (input == null) {
            throw new IllegalArgumentException('Input map must not be null');
        }
    }

    public static String requireString(Map<String, Object> input, String key) {
        if (!input.containsKey(key) || input.get(key) == null) {
            throw new IllegalArgumentException('Missing required input parameter: ' + key);
        }
        if (!(input.get(key) instanceof String)) {
            throw new IllegalArgumentException('Input parameter ' + key + ' must be a string');
        }
        String value = ((String) input.get(key)).trim();
        if (String.isBlank(value)) {
            throw new IllegalArgumentException('Input parameter ' + key + ' must not be blank');
        }
        return value;
    }

    public static String optionalString(Map<String, Object> input, String key) {
        if (!input.containsKey(key) || input.get(key) == null) {
            return null;
        }
        if (!(input.get(key) instanceof String)) {
            throw new IllegalArgumentException('Input parameter ' + key + ' must be a string');
        }
        return (String) input.get(key);
    }

    public static Boolean requireBoolean(Map<String, Object> input, String key) {
        if (!input.containsKey(key) || input.get(key) == null) {
            throw new IllegalArgumentException(
                'Missing required input parameter: ' + key + ' (expected true or false)'
            );
        }
        if (!(input.get(key) instanceof Boolean)) {
            throw new IllegalArgumentException(
                'Input parameter ' + key + ' must be a boolean (true or false), received: ' + input.get(key)
            );
        }
        return (Boolean) input.get(key);
    }

    public static List<Object> requireList(Map<String, Object> input, String key) {
        if (!input.containsKey(key) || input.get(key) == null) {
            throw new IllegalArgumentException('Missing required input parameter: ' + key);
        }
        if (!(input.get(key) instanceof List<Object>)) {
            throw new IllegalArgumentException('Input parameter ' + key + ' must be an array');
        }
        return (List<Object>) input.get(key);
    }
}
