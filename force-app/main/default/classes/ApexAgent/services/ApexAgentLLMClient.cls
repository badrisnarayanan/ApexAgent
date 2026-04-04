/**
 * Handles HTTP callouts to the OpenRouter chat completions endpoint.
 * Serializes the request, enforces timeout, and parses the response.
 */
public with sharing class ApexAgentLLMClient {

    private static final Integer TIMEOUT_MS = 120000;

    /**
     * Sends a chat completion request to the configured LLM endpoint.
     * Throws a CalloutException if the response status is not 2xx.
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
        System.debug(LoggingLevel.DEBUG,  'Request Body: ' +    serializedBody);
        req.setBody(serializedBody);
        req.setTimeout(TIMEOUT_MS);

        Http http = new Http();
        HttpResponse resp = http.send(req);

        if (resp.getStatusCode() < 200 || resp.getStatusCode() >= 300) {
            throw new CalloutException(
                'LLM callout failed. Status: ' + resp.getStatusCode()
                + ' Body: ' + resp.getBody()
            );
        }

        return (ApexAgentApiTypes.ChatCompletionResponse) JSON.deserialize(
            resp.getBody(),
            ApexAgentApiTypes.ChatCompletionResponse.class
        );
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
