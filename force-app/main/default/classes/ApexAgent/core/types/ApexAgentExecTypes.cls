/**
 * Internal execution types for the ApexAgent framework.
 * Used for passing tool execution results between framework components.
 */
public with sharing class ApexAgentExecTypes {

    /** Values of ToolResult.status. */
    public static final String STATUS_SUCCESS = 'success';
    public static final String STATUS_ERROR   = 'error';

    /** Result of a single tool execution, including metadata and outcome. */
    public class ToolResult {
        public String toolId;
        public String name;
        public String implementation;
        public String inputArguments;
        public String output;
        public String status;
        public String errorMessage;
        public String errorStackTrace;

        public Boolean isError() {
            return STATUS_ERROR.equals(status);
        }
    }
}
