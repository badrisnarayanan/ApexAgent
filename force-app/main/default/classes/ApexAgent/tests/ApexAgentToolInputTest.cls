@IsTest
private class ApexAgentToolInputTest {

    @IsTest
    static void testRequireNotBlank() {
        Assert.areEqual('hello', ApexAgentToolInput.requireNotBlank('  hello  ', 'name'), 'Should trim and return value');

        try {
            ApexAgentToolInput.requireNotBlank(null, 'missing');
            Assert.fail('Expected exception for null value');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('missing'), 'Should mention the param name');
        }

        try {
            ApexAgentToolInput.requireNotBlank('   ', 'blank');
            Assert.fail('Expected exception for blank value');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Should mention blank');
        }
    }
}
