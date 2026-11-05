/**
 * Creates the adapter for an agent's Model Provider record: a built-in one for
 * each provider type, or the developer's own class when the type is Custom.
 */
public with sharing class ApexAgentLLMProviderFactory {

    public static ApexAgentLLMProvider create(ApexAgentConfigTypes.AgentConfig config) {
        ApexAgentLLMProvider provider = newAdapter(config);
        provider.setConfig(config);
        return provider;
    }

    private static ApexAgentLLMProvider newAdapter(ApexAgentConfigTypes.AgentConfig config) {
        switch on config.providerType {
            when 'OpenAI', 'Azure_OpenAI' {
                return new ApexAgentOpenAIProvider();
            }
            when 'OpenRouter' {
                return new ApexAgentOpenRouterProvider();
            }
            when 'Google_AI_Studio' {
                return new ApexAgentGeminiProvider();
            }
            when 'Custom' {
                return newCustomAdapter(config);
            }
            when else {
                throw new ApexAgentLLMProvider.ProviderException('Model Provider "' + config.providerName
                    + '" has provider type "' + config.providerType + '", which ApexAgent doesn\'t support.');
            }
        }
    }

    private static ApexAgentLLMProvider newCustomAdapter(ApexAgentConfigTypes.AgentConfig config) {
        String about = 'Model Provider "' + config.providerName + '" names Apex class "' + config.providerApexClass + '"';
        Type adapterType = String.isBlank(config.providerApexClass) ? null : Type.forName(config.providerApexClass);
        if (adapterType == null) {
            throw new ApexAgentLLMProvider.ProviderException(about + ', which doesn\'t exist or isn\'t visible.');
        }
        Object instance;
        try {
            instance = adapterType.newInstance();
        } catch (Exception e) {
            throw new ApexAgentLLMProvider.ProviderException(about
                + ', which couldn\'t be created. It needs a public no-argument constructor. ' + e.getMessage());
        }
        if (!(instance instanceof ApexAgentLLMProvider)) {
            throw new ApexAgentLLMProvider.ProviderException(about + ', which doesn\'t extend ApexAgentLLMProvider.');
        }
        return (ApexAgentLLMProvider) instance;
    }
}
