/**
 * OpenAI and Azure OpenAI (v1 API), and any gateway that follows the OpenAI
 * chat completions spec. Azure's api-key header and deployment name are
 * configuration (the named credential and Model API Name), not code.
 *
 * reasoning_effort: left out when the LLM record says the model doesn't
 * reason, because non-reasoning models (gpt-4o, gpt-4.1) reject the field.
 * When the model reasons but the agent disables reasoning, "none" is sent:
 * newer OpenAI models reason by default and can't combine that with tools.
 *
 * If a request is still rejected over reasoning_effort, the adapter resends it
 * once with a corrected value, remembers that value for this provider and
 * model (for the transaction, and in org Platform Cache across transactions),
 * and records a warning for the admin. It can't update the LLM record itself:
 * DML mid-turn would block the next callout.
 */
public with sharing class ApexAgentOpenAIProvider extends ApexAgentLLMProvider {

    @TestVisible
    private static final String EFFORT_NONE = 'none';
    @TestVisible
    private static final String EFFORT_OMIT = 'omit';

    private static final String REASONING_PARAM   = 'reasoning_effort';
    private static final String TOOLS_WITH_EFFORT = 'Function tools with reasoning_effort';
    private static final String CACHE_PARTITION   = 'local.ApexAgentExecution';
    private static final Integer CACHE_TTL_SECONDS = 86400;

    /** Remembered corrections for this transaction, keyed like the cache. */
    private static final Map<String, String> CORRECTIONS_BY_KEY = new Map<String, String>();

    protected override String mapReasoningEffort() {
        String correction = rememberedCorrection();
        if (correction == EFFORT_OMIT) {
            return null;
        }
        if (config.supportsReasoning != true) {
            return null;
        }
        if (correction == EFFORT_NONE || config.reasoningEffort == 'disabled') {
            return EFFORT_NONE;
        }
        return String.isBlank(config.reasoningEffort) ? null : config.reasoningEffort;
    }

    /**
     * A 400 on reasoning_effort gets one corrected resend:
     *   "Function tools with reasoning_effort ..."  resend with none
     *   any other rejection of reasoning_effort      resend without the field
     */
    public override Map<String, Object> retryBodyAfterRejection(
        Integer statusCode,
        String responseBody,
        Map<String, Object> requestBody
    ) {
        if (statusCode != 400 || !requestBody.containsKey(REASONING_PARAM)
                || !isReasoningEffortError(responseBody)) {
            return null;
        }
        String sent = String.valueOf(requestBody.get(REASONING_PARAM));
        Boolean toolsConflict = responseBody.contains(TOOLS_WITH_EFFORT) && sent != EFFORT_NONE;
        String correction = toolsConflict ? EFFORT_NONE : EFFORT_OMIT;

        Map<String, Object> corrected = requestBody.clone();
        if (toolsConflict) {
            corrected.put(REASONING_PARAM, EFFORT_NONE);
            addWarning('Model "' + config.modelApiName + '" on provider "' + config.providerName
                + '" can\'t use tools and reasoning together on chat completions, so ApexAgent resent the request with '
                + 'reasoning_effort "none". Set Reasoning Effort to disabled on the agent so it sends "none" from the start.');
        } else {
            corrected.remove(REASONING_PARAM);
            addWarning('Model "' + config.modelApiName + '" on provider "' + config.providerName
                + '" rejected reasoning_effort "' + sent + '", so ApexAgent resent the request without it and '
                + 'leaves it out for this model from now on. If the model doesn\'t reason, untick Supports Reasoning on this LLM record.');
        }
        rememberCorrection(correction);
        return corrected;
    }

    /** OpenAI names the field in param; some errors (and Azure) name it only in the message. */
    private static Boolean isReasoningEffortError(String responseBody) {
        try {
            Map<String, Object> error = asMap(asMap(JSON.deserializeUntyped(responseBody))?.get('error'));
            return error != null && (error.get('param') == REASONING_PARAM
                || asString(error.get('message'))?.contains(REASONING_PARAM) == true);
        } catch (JSONException e) {
            // A non-JSON error body can't name the parameter, so it isn't this case.
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Remembered corrections
    // ─────────────────────────────────────────────────────────────────

    private String rememberedCorrection() {
        String key = correctionKey();
        if (CORRECTIONS_BY_KEY.containsKey(key)) {
            return CORRECTIONS_BY_KEY.get(key);
        }
        String cached = null;
        try {
            Object value = Cache.Org.get(CACHE_PARTITION + '.' + key);
            cached = value == null ? null : String.valueOf(value);
        } catch (Exception e) {
            // An org without cache capacity just pays the one resend each transaction.
            System.debug(LoggingLevel.FINE, 'ApexAgentOpenAIProvider: cache read skipped: ' + e.getMessage());
        }
        CORRECTIONS_BY_KEY.put(key, cached);
        return cached;
    }

    private void rememberCorrection(String correction) {
        String key = correctionKey();
        CORRECTIONS_BY_KEY.put(key, correction);
        try {
            Cache.Org.put(CACHE_PARTITION + '.' + key, correction, CACHE_TTL_SECONDS);
        } catch (Exception e) {
            System.debug(LoggingLevel.FINE, 'ApexAgentOpenAIProvider: cache write skipped: ' + e.getMessage());
        }
    }

    /**
     * Cache keys must be alphanumeric and short, so the inputs are hashed. The
     * reasoning settings are part of the key, so an admin's fix to the LLM or
     * agent takes effect at once instead of being overridden by an old correction.
     */
    private String correctionKey() {
        String source = String.valueOf(config.providerId) + '|' + config.modelApiName
            + '|' + config.supportsReasoning + '|' + config.reasoningEffort;
        return 'rsn' + EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(source)));
    }
}
