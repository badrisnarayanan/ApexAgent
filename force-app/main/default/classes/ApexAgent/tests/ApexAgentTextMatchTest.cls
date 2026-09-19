@IsTest
private class ApexAgentTextMatchTest {

    @IsTest
    static void testSplitCamelCase() {
        Assert.areEqual(new List<String>{ 'tech', 'nova' }, ApexAgentTextMatch.splitCamelCase('TechNova'), 'PascalCase');
        Assert.areEqual(new List<String>{ 'opportunity', 'line', 'item' }, ApexAgentTextMatch.splitCamelCase('OpportunityLineItem'), 'three words');
        Assert.areEqual(new List<String>{ 'i', 'phone' }, ApexAgentTextMatch.splitCamelCase('iPhone'), 'lower-first camelCase');
        Assert.areEqual(new List<String>{ 'mc', 'donald' }, ApexAgentTextMatch.splitCamelCase('McDonald'), 'McDonald');
        Assert.areEqual(new List<String>{ 'ibm', 'global' }, ApexAgentTextMatch.splitCamelCase('IBMGlobal'), 'acronym followed by a word');
        Assert.areEqual(new List<String>{ 'ibm' }, ApexAgentTextMatch.splitCamelCase('IBM'), 'all caps stays whole');
        Assert.areEqual(new List<String>{ 'account' }, ApexAgentTextMatch.splitCamelCase('account'), 'lowercase stays whole');
        Assert.areEqual(new List<String>{ 'account' }, ApexAgentTextMatch.splitCamelCase('Account'), 'single capitalised word');
        Assert.areEqual(new List<String>{ 'web3', 'provider' }, ApexAgentTextMatch.splitCamelCase('Web3Provider'), 'capital after a digit starts a word');
        Assert.areEqual(new List<String>{ 'abc123' }, ApexAgentTextMatch.splitCamelCase('abc123'), 'trailing digits stay attached');
        Assert.isTrue(ApexAgentTextMatch.splitCamelCase(null).isEmpty(), 'null');
        Assert.isTrue(ApexAgentTextMatch.splitCamelCase('  ').isEmpty(), 'blank');
    }

    @IsTest
    static void testWordSet() {
        Set<String> words = ApexAgentTextMatch.wordSet('TechNova Inc_Global');
        Assert.isTrue(words.containsAll(new List<String>{ 'technova', 'tech', 'nova', 'inc', 'global' }),
            'Whole tokens and camelCase parts should both be present — got: ' + words);
        Assert.isTrue(ApexAgentTextMatch.wordSet(null).isEmpty(), 'null text');
    }

    @IsTest
    static void testWordOverlap() {
        // A perfect single-word match is 1 — never diluted by guessed fragments
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('Accenture', ApexAgentTextMatch.wordSet('Accenture')), 'Accenture');
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('IBM', ApexAgentTextMatch.wordSet('IBM Global Services')), 'IBM');

        // Fraction of the typed tokens found
        Assert.areEqual(0.5, ApexAgentTextMatch.wordOverlap('Global Widgets', ApexAgentTextMatch.wordSet('IBM Global Services')), 'one of two words');
        Assert.areEqual(0.0, ApexAgentTextMatch.wordOverlap('Widgets', ApexAgentTextMatch.wordSet('IBM Global Services')), 'no words');
        Assert.areEqual(0.0, ApexAgentTextMatch.wordOverlap('   ', ApexAgentTextMatch.wordSet('IBM')), 'blank term');

        // camelCase, spacing and case differences between the term and the text
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('TechNova', ApexAgentTextMatch.wordSet('Tech Nova Partners')), 'camel term vs spaced name');
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('technova', ApexAgentTextMatch.wordSet('TechNova Partners')), 'lowercase term vs camel name');
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('Nova', ApexAgentTextMatch.wordSet('TechNova Partners')), 'word inside a camel name');
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('line item', ApexAgentTextMatch.wordSet('OpportunityLineItem')), 'spaced term vs API name');

        // Plural / singular
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('accounts', ApexAgentTextMatch.wordSet('Account')), 'plural term');
        Assert.areEqual(1.0, ApexAgentTextMatch.wordOverlap('company', ApexAgentTextMatch.wordSet('Companies')), 'singular term');
    }

    @IsTest
    static void testPluralSingularVariants() {
        Assert.isTrue(ApexAgentTextMatch.pluralSingularVariants('company').contains('companies'), 'y → ies');
        Assert.isTrue(ApexAgentTextMatch.pluralSingularVariants('boxes').contains('box'), 'xes → x');
        Assert.isTrue(ApexAgentTextMatch.pluralSingularVariants('account').contains('accounts'), '+s');
        Assert.isTrue(ApexAgentTextMatch.pluralSingularVariants('a').isEmpty(), 'too short');
    }

    @IsTest
    static void testSplitCompoundAndSimilarity() {
        // Search-pattern candidates: parts, camelCase words, and the speculative splits
        Set<String> words = new Set<String>(ApexAgentTextMatch.splitCompound('Work_OrderItem'));
        Assert.isTrue(words.containsAll(new List<String>{ 'work', 'order', 'item', 'orderitem' }),
            'Parts and camelCase words expected — got: ' + words);
        Assert.isTrue(new Set<String>(ApexAgentTextMatch.splitCompound('mapping')).containsAll(new List<String>{ 'map', 'ping' }),
            'Doubled-consonant split');
        Assert.isTrue(new Set<String>(ApexAgentTextMatch.splitCompound('accenture')).contains('centure'),
            'Doubled-consonant split of accenture');
        Assert.isTrue(new Set<String>(ApexAgentTextMatch.splitCompound('workorderitem')).containsAll(new List<String>{ 'worko', 'rderitem' }),
            'Vowel-to-consonant split needs both halves to be 4+ characters');
        Assert.isFalse(new Set<String>(ApexAgentTextMatch.splitCompound('order')).contains('or'),
            'Terms under 8 characters get no vowel-to-consonant splits');
        Assert.isFalse(new Set<String>(ApexAgentTextMatch.splitCompound('  ')).contains(''), 'No blank words');

        // Levenshtein similarity
        Assert.areEqual(1.0, ApexAgentTextMatch.levenshteinSimilarity('account', 'account'), 'identical');
        Assert.areEqual(0.0, ApexAgentTextMatch.levenshteinSimilarity('abc', 'xyz'), 'nothing in common');
        Assert.areEqual(0.0, ApexAgentTextMatch.levenshteinSimilarity(null, 'abc'), 'null');
        Assert.areEqual(0.0, ApexAgentTextMatch.levenshteinSimilarity('abc', '  '), 'blank');
        Assert.areEqual(0.75, ApexAgentTextMatch.levenshteinSimilarity('case', 'cast'), 'one substitution in four characters');
        Assert.areEqual(0.5, ApexAgentTextMatch.levenshteinSimilarity('ab', 'abcd'), 'two insertions over the longer length');
    }
}
