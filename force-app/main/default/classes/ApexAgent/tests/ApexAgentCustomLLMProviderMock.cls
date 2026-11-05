/**
 * A developer's own adapter, as a Custom Model Provider names it. Overrides
 * one hook to show the factory returns this class and the hooks are used.
 */
@IsTest
public class ApexAgentCustomLLMProviderMock extends ApexAgentLLMProvider {

    public override String endpoint() {
        return 'callout:' + config.namedCredential + '/custom/chat';
    }
}
