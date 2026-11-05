/**
 * Sends a chat completion request through a provider adapter and retries
 * transient failures. Everything provider-specific (request body, response
 * parsing, which failures to retry) is decided by the adapter.
 *
 * Retries up to MAX_RETRIES times on network errors and on failures the
 * adapter calls retryable. Apex can't pause between attempts, so a provider
 * that asks to wait longer than MAX_RETRY_AFTER_SECONDS fails the call instead
 * of being hit again straight away.
 */
public with sharing class ApexAgentLLMClient {

    private static final Integer TIMEOUT_MS = 120000;
    private static final Integer MAX_RETRIES = 3;
    private static final Integer MAX_RETRY_AFTER_SECONDS = 5;

    public static ApexAgentLLMTypes.LLMResult call(
        ApexAgentLLMProvider provider,
        List<Object> messages,
        List<Map<String, Object>> toolDefs
    ) {
        Map<String, Object> body = provider.buildRequestBody(messages, toolDefs);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(provider.endpoint());
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);

        Http http = new Http();
        Integer attempt = 0;
        Boolean resentAfterRejection = false;
        req.setBody(JSON.serialize(body, true));

        while (true) {
            attempt++;

            // Network-level failures (timeout, DNS, connection reset) are always
            // transient, so only send() is inside this catch.
            HttpResponse resp;
            try {
                resp = http.send(req);
            } catch (CalloutException e) {
                if (attempt > MAX_RETRIES) {
                    throw new CalloutException(
                        'LLM callout failed after ' + attempt + ' attempt(s): ' + e.getMessage()
                    );
                }
                continue;
            }

            Integer statusCode = resp.getStatusCode();
            String responseBody = resp.getBody();
            if (statusCode >= 200 && statusCode < 300) {
                return provider.parseResponse(responseBody);
            }

            if (!resentAfterRejection) {
                Map<String, Object> corrected = provider.retryBodyAfterRejection(statusCode, responseBody, body);
                if (corrected != null) {
                    body = corrected;
                    req.setBody(JSON.serialize(body, true));
                    resentAfterRejection = true;
                    continue;
                }
            }

            if (!provider.isRetryable(statusCode, responseBody)) {
                throw new CalloutException(
                    'LLM callout failed with non-retryable status. Status: ' + statusCode + ' Body: ' + responseBody
                );
            }
            if (attempt > MAX_RETRIES) {
                throw new CalloutException('LLM callout failed after ' + attempt + ' attempt(s). Status: '
                    + statusCode + ' Body: ' + responseBody);
            }
            Integer retryAfter = retryAfterSeconds(resp.getHeader('Retry-After'));
            if (retryAfter != null && retryAfter > MAX_RETRY_AFTER_SECONDS) {
                throw new CalloutException('LLM provider asked to wait ' + retryAfter
                    + ' seconds before retrying. Status: ' + statusCode + ' Body: ' + responseBody);
            }
        }
        return null; // unreachable: the loop always returns or throws, but the compiler requires it
    }

    /** Retry-After in seconds, or null when absent or given as an HTTP date. */
    private static Integer retryAfterSeconds(String header) {
        return String.isNotBlank(header) && header.trim().isNumeric() ? Integer.valueOf(header.trim()) : null;
    }
}
