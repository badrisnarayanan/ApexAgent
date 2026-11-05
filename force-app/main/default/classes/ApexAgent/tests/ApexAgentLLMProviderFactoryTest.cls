/**
 * ApexAgentLLMProviderFactory: the built-in adapter for each provider type, a
 * developer's own class for Custom, and a clear error naming the provider
 * record and class when a Custom class can't be used.
 */
@IsTest
private class ApexAgentLLMProviderFactoryTest {

    private static ApexAgentLLMProvider create(String providerType, String apexClass) {
        ApexAgentConfigTypes.AgentConfig cfg = ApexAgentTestDataFactory.newAgentConfig(providerType);
        cfg.providerApexClass = apexClass;
        return ApexAgentLLMProviderFactory.create(cfg);
    }

    private static String errorFor(String providerType, String apexClass) {
        try {
            create(providerType, apexClass);
            Assert.fail('Expected a ProviderException for ' + providerType + ' / ' + apexClass);
        } catch (ApexAgentLLMProvider.ProviderException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void testBuiltInAndCustomAdapters() {
        Assert.isInstanceOfType(create('OpenAI', null), ApexAgentOpenAIProvider.class, 'OpenAI');
        Assert.isInstanceOfType(create('Azure_OpenAI', null), ApexAgentOpenAIProvider.class, 'Azure shares the OpenAI adapter');
        Assert.isInstanceOfType(create('OpenRouter', null), ApexAgentOpenRouterProvider.class, 'OpenRouter');
        Assert.isInstanceOfType(create('Google_AI_Studio', null), ApexAgentGeminiProvider.class, 'AI Studio');

        ApexAgentLLMProvider custom = create('Custom', 'ApexAgentCustomLLMProviderMock');
        Assert.isInstanceOfType(custom, ApexAgentCustomLLMProviderMock.class, 'Custom should create the named class');
        Assert.areEqual('callout:TestCredential/custom/chat', custom.endpoint(), 'The custom class should get the config');
        Assert.areEqual('low', custom.buildRequestBody(new List<Object>(), null).get('reasoning_effort'),
            'Hooks a custom class doesn\'t override should keep the OpenAI defaults');
    }

    @IsTest
    static void testUnusableProvidersFailWithClearMessages() {
        String missing = errorFor('Custom', 'NoSuchApexAgentProvider');
        Assert.isTrue(missing.contains('"Test Provider"') && missing.contains('"NoSuchApexAgentProvider"')
            && missing.contains('doesn\'t exist'), missing);

        String blank = errorFor('Custom', null);
        Assert.isTrue(blank.contains('doesn\'t exist'), blank);

        String wrongType = errorFor('Custom', 'ApexAgentTestDataFactory');
        Assert.isTrue(wrongType.contains('doesn\'t extend ApexAgentLLMProvider'), wrongType);

        String unknownType = errorFor('Bedrock', null);
        Assert.isTrue(unknownType.contains('provider type "Bedrock"'), unknownType);
    }
}
