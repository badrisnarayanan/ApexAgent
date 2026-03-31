public interface ApexAgentParameterDefinition {
    /**
     * Returns an OpenAI function-calling compatible JSON schema fragment
     * for this parameter. Serialise the returned map to get the JSON
     * to embed in the tool's "parameters.properties" block.
     */
    Map<String, Object> getDefinition();
}
