/**
 * OpenAI API request/response wrapper types for the ApexAgent framework.
 */
public with sharing class ApexAgentApiTypes {

    /** Represents a single tool call in an OpenAI chat completions response. */
    public class ToolCall {
        public String id;
        public String type;
        public ToolCallFunction function;
    }

    /** The function details within a tool call. */
    public class ToolCallFunction {
        public String name;
        /** JSON-encoded string of the function arguments as sent by the LLM. */
        public String arguments;
    }
}
