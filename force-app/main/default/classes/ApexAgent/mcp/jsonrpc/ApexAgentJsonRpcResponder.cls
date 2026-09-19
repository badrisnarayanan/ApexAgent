/**
 * Writes JSON-RPC 2.0 success and error bodies onto the current REST response.
 * Errors default to HTTP 200 (a JSON-RPC error is still a valid response);
 * pass an explicit HTTP status where the transport requires one, e.g. 400 for
 * a malformed message or 404 for an unknown method.
 */
public with sharing class ApexAgentJsonRpcResponder {

    public static void success(Object id, Object result) {
        write(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => id,
            'result' => result
        });
    }

    public static void error(Object id, Integer code, String message) {
        error(200, id, code, message);
    }

    public static void error(Integer httpStatus, Object id, Integer code, String message) {
        RestContext.response.statusCode = httpStatus;
        write(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => id,
            'error' => new Map<String, Object>{
                'code' => code,
                'message' => message
            }
        });
    }

    /** A notification was accepted: HTTP 202 with no body. */
    public static void accepted() {
        RestContext.response.statusCode = 202;
    }

    private static void write(Map<String, Object> body) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
