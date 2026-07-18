/**
 * Internal REST resource that executes data-modifying tools in an isolated
 * transaction, allowing the main orchestration thread to make subsequent
 * LLM API callouts without triggering a DML-before-callout error.
 *
 * Called exclusively by ApexAgentToolExecutor for tools where
 * Modifies_Salesforce_Data__c = true.
 */
@RestResource(urlMapping='/ApexAgent/dml-bridge')
global with sharing class ApexAgentDmlBridgeResource {

    public class BridgeException extends Exception {
        public String originalStackTrace;
        public BridgeException(String message, String stackTrace) {
            this.setMessage(message);
            this.originalStackTrace = stackTrace;
        }
    }

    /**
     * Accepts a tool execution request, runs it, and writes the result directly to the
     * response body. Returns void (rather than String) so the platform does not
     * JSON-serialize an already-JSON-serialized payload a second time.
     * On failure, responds with HTTP 500 and a JSON error body.
     *
     * Expected request body:
     * {
     *   "executionType": "Apex" | "Flow",
     *   "executionName": "<class or flow API name>",
     *   "inputs": { ... }
     * }
     */
    @HttpPost
    global static void execute() {
        String responseBody;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.request.requestBody.toString()
            );

            String executionType = (String) body.get('executionType');
            String executionName = (String) body.get('executionName');
            Map<String, Object> inputs = (Map<String, Object>) body.get('inputs');

            responseBody = ApexAgentToolExecutor.executeInline(executionType, executionName, inputs);

        } catch (Exception e) {
            RestContext.response.statusCode = 500;
            responseBody = JSON.serialize(new Map<String, Object>{
                'error'      => e.getMessage(),
                'type'       => e.getTypeName(),
                'stackTrace' => e.getStackTraceString()
            });
        }
        RestContext.response.headers.put('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(responseBody);
    }
}
