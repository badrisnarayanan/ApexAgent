/**
 * Handles HTTP callouts to the OpenRouter chat completions endpoint.
 * Serializes the request, enforces timeout, and parses the response.
 * Retries up to MAX_RETRIES times on transient errors (network failures, 429, 5xx).
 */
public with sharing class ApexAgentLLMClient {

    private static final Integer TIMEOUT_MS = 120000;
    private static final Integer MAX_RETRIES = 3;
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 429, 500, 502, 503, 504 };

    /**
     * Sends a chat completion request to the configured LLM endpoint.
     * Retries on network errors and retryable HTTP status codes.
     * Throws a CalloutException if all attempts fail or a non-retryable error occurs.
     */
    public static ApexAgentApiTypes.ChatCompletionResponse call(
        ApexAgentConfigTypes.AgentConfig config,
        List<Object> messages,
        List<Map<String, Object>> toolDefs
    ) {
        Map<String, Object> body = buildRequestBody(config, messages, toolDefs);

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + config.namedCredential + config.chatCompletionsPath);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        String serializedBody = JSON.serialize(body, true);
        System.debug(LoggingLevel.DEBUG, 'Request Body: ' + serializedBody);
        req.setBody(serializedBody);
        req.setTimeout(TIMEOUT_MS);

        Http http = new Http();
        Integer attempt = 0;

        while (true) {
            attempt++;
            try {
                HttpResponse resp = http.send(req);
                Integer statusCode = resp.getStatusCode();

                if (statusCode >= 200 && statusCode < 300) {
                    return (ApexAgentApiTypes.ChatCompletionResponse) JSON.deserialize(
                        resp.getBody(),
                        ApexAgentApiTypes.ChatCompletionResponse.class
                    );
                }

                if (!RETRYABLE_STATUS_CODES.contains(statusCode) || attempt > MAX_RETRIES) {
                    throw new CalloutException(
                        'LLM callout failed after ' + attempt + ' attempt(s).'
                        + ' Status: ' + statusCode
                        + ' Body: ' + resp.getBody()
                    );
                }

                System.debug(LoggingLevel.WARN,
                    'LLM callout attempt ' + attempt + ' returned ' + statusCode + '. Retrying...'
                );

            } catch (CalloutException e) {
                if (attempt > MAX_RETRIES) {
                    throw new CalloutException(
                        'LLM callout failed after ' + attempt + ' attempt(s): ' + e.getMessage()
                    );
                }
                System.debug(LoggingLevel.WARN,
                    'LLM callout attempt ' + attempt + ' threw exception: ' + e.getMessage() + '. Retrying...'
                );
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────

    private static Map<String, Object> buildRequestBody(
        ApexAgentConfigTypes.AgentConfig config,
        List<Object> messages,
        List<Map<String, Object>> toolDefs
    ) {
        Map<String, Object> body = new Map<String, Object>{
            'model'      => config.modelApiName,
            'messages'   => messages,
            'max_tokens' => config.maxTokens,
            'stream'     => false
        };

        if (!toolDefs.isEmpty()) {
            body.put('tools', toolDefs);
            body.put('tool_choice', 'auto');
        }

        if (String.isNotBlank(config.reasoningEffort)
                && config.reasoningEffort != 'disabled') {
            body.put('reasoning', new Map<String, Object>{
                'effort' => config.reasoningEffort
            });
        }

        return body;
    }
}
