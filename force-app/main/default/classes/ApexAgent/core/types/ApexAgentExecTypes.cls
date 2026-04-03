/**
 * Internal execution types for the ApexAgent framework.
 * Used for passing tool execution results between framework components.
 */
public with sharing class ApexAgentExecTypes {

    /** Result of a single tool execution, including metadata and outcome. */
    public class ToolResult {
        public String toolId;
        public String name;
        public String type;
        public String implementation;
        public String inputArguments;
        public String output;
        public String status;
        public String errorMessage;
        public String errorStackTrace;
    }
}
