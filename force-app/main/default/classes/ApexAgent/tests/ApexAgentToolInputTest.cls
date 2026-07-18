@IsTest
private class ApexAgentToolInputTest {

    @IsTest
    static void testRequireMap() {
        try {
            ApexAgentToolInput.requireMap(null);
            Assert.fail('Expected exception for null map');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('null'), 'Should mention null');
        }
        // Non-null map — no exception
        ApexAgentToolInput.requireMap(new Map<String, Object>());
    }

    @IsTest
    static void testRequireString() {
        Map<String, Object> input = new Map<String, Object>{
            'name' => '  hello  ', 'blank' => '   ', 'wrongType' => 42
        };

        Assert.areEqual('hello', ApexAgentToolInput.requireString(input, 'name'), 'Should trim and return value');

        try {
            ApexAgentToolInput.requireString(input, 'missing');
            Assert.fail('Expected exception for missing key');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('missing'), 'Should mention the key name');
        }

        try {
            ApexAgentToolInput.requireString(input, 'blank');
            Assert.fail('Expected exception for blank value');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('blank'), 'Should mention blank');
        }

        try {
            ApexAgentToolInput.requireString(input, 'wrongType');
            Assert.fail('Expected exception for non-string value');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('wrongType'), 'Should mention the key name');
        }
    }

    @IsTest
    static void testOptionalString() {
        Map<String, Object> input = new Map<String, Object>{ 'present' => 'value', 'wrongType' => true };

        Assert.areEqual('value', ApexAgentToolInput.optionalString(input, 'present'), 'Should return present value');
        Assert.isNull(ApexAgentToolInput.optionalString(input, 'absent'), 'Missing key should return null');

        try {
            ApexAgentToolInput.optionalString(input, 'wrongType');
            Assert.fail('Expected exception for non-string value');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('wrongType'), 'Should mention the key name');
        }
    }

    @IsTest
    static void testRequireBoolean() {
        Map<String, Object> input = new Map<String, Object>{ 'flag' => true, 'wrongType' => 'true' };

        Assert.areEqual(true, ApexAgentToolInput.requireBoolean(input, 'flag'), 'Should return boolean value');

        try {
            ApexAgentToolInput.requireBoolean(input, 'missing');
            Assert.fail('Expected exception for missing key');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('missing'), 'Should mention the key name');
        }

        try {
            ApexAgentToolInput.requireBoolean(input, 'wrongType');
            Assert.fail('Expected exception for non-boolean value (string "true")');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('wrongType'), 'Should mention the key name');
        }
    }

    @IsTest
    static void testRequireList() {
        Map<String, Object> input = new Map<String, Object>{
            'items' => new List<Object>{ 1, 2 }, 'wrongType' => new Map<String, Object>()
        };

        Assert.areEqual(2, ApexAgentToolInput.requireList(input, 'items').size(), 'Should return the list');

        try {
            ApexAgentToolInput.requireList(input, 'missing');
            Assert.fail('Expected exception for missing key');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('missing'), 'Should mention the key name');
        }

        try {
            ApexAgentToolInput.requireList(input, 'wrongType');
            Assert.fail('Expected exception for non-list value');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('wrongType'), 'Should mention the key name');
        }
    }
}
