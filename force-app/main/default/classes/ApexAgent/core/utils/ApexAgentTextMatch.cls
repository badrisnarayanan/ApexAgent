/**
 * Text-matching helpers shared by the fuzzy-search tools (SearchRecords, SearchObjects):
 * camelCase splitting, plural/singular variants, and a word-overlap measure used for scoring.
 */
public with sharing class ApexAgentTextMatch {

    private static final String WORD_SEPARATORS = '[\\s_]+';

    /**
     * Splits a camelCase / PascalCase term into lowercase words: "TechNova" → tech, nova;
     * "IBMGlobal" → ibm, global; "Web3Provider" → web3, provider; "IBM" and "account" stay whole. The case checks use
     * equals() — Apex's == on strings is case-insensitive, so it can't tell 'B' from 'b'.
     */
    public static List<String> splitCamelCase(String term) {
        List<String> words = new List<String>();
        if (String.isBlank(term)) {
            return words;
        }
        Integer wordStart = 0;
        for (Integer i = 1; i < term.length(); i++) {
            if (!isUpper(term.substring(i, i + 1))) {
                continue;
            }
            Boolean afterLower = isLower(term.substring(i - 1, i)) || term.substring(i - 1, i).isNumeric();
            Boolean endsAcronym = isUpper(term.substring(i - 1, i))
                && i + 1 < term.length() && isLower(term.substring(i + 1, i + 2));
            if (afterLower || endsAcronym) {
                words.add(term.substring(wordStart, i).toLowerCase());
                wordStart = i;
            }
        }
        words.add(term.substring(wordStart).toLowerCase());
        return words;
    }

    /**
     * The words of a piece of text (a record name, an object API name or label) for
     * matching against a search term: each whitespace/underscore-separated token,
     * lowercased whole, plus its camelCase parts.
     */
    public static Set<String> wordSet(String text) {
        Set<String> words = new Set<String>();
        if (String.isBlank(text)) {
            return words;
        }
        for (String token : text.split(WORD_SEPARATORS)) {
            if (String.isNotBlank(token)) {
                words.add(token.toLowerCase());
                words.addAll(splitCamelCase(token));
            }
        }
        return words;
    }

    /**
     * Fraction (0 to 1) of the search term's words that appear in textWords (from
     * wordSet). The search term is counted by its own whitespace/underscore-separated
     * tokens only — not by guessed sub-word fragments — so a name that contains every
     * word the caller typed scores 1. A token matches as itself, as a plural/singular
     * variant, or as all of its camelCase parts.
     */
    public static Double wordOverlap(String searchTerm, Set<String> textWords) {
        Integer total = 0;
        Integer matched = 0;
        for (String token : searchTerm.split(WORD_SEPARATORS)) {
            if (String.isBlank(token)) {
                continue;
            }
            total++;
            String lower = token.toLowerCase();
            List<String> parts = splitCamelCase(token);
            if (textWords.contains(lower)
                    || (parts.size() > 1 && textWords.containsAll(parts))
                    || containsAny(textWords, pluralSingularVariants(lower))) {
                matched++;
            }
        }
        return total == 0 ? 0.0 : (Double) matched / total;
    }

    /**
     * Candidate words for a search term, used to widen a search: each whitespace/underscore
     * separated part (plus its camelCase words) and speculative splits of the joined term at
     * doubled consonants and vowel-to-consonant boundaries. These are guesses, so they are
     * for generating search patterns only — use wordOverlap for scoring.
     */
    public static List<String> splitCompound(String term) {
        Set<String> wordSet = new Set<String>();
        for (String part : term.split(WORD_SEPARATORS)) {
            if (String.isNotBlank(part)) {
                wordSet.add(part.toLowerCase());
                wordSet.addAll(splitCamelCase(part));
            }
        }
        String lower = term.toLowerCase().replaceAll('[\\s_]', '');
        wordSet.addAll(splitDoubledConsonants(lower));
        wordSet.addAll(splitVowelConsonant(lower));
        wordSet.remove('');
        return new List<String>(wordSet);
    }

    /** "mapping" → map, ping: splits between a doubled consonant when both halves are 2+ characters. */
    private static Set<String> splitDoubledConsonants(String term) {
        Set<String> parts = new Set<String>();
        String vowels = 'aeiou';
        for (Integer i = 1; i < term.length(); i++) {
            String prev = term.substring(i - 1, i);
            String curr = term.substring(i, i + 1);
            if (prev == curr && !vowels.contains(prev)) {
                String left = term.substring(0, i);
                String right = term.substring(i);
                if (left.length() >= 2 && right.length() >= 2) {
                    parts.add(left);
                    parts.add(right);
                }
            }
        }
        return parts;
    }

    /** Splits a long term (8+ characters) at a vowel-to-consonant boundary when both halves are 4+ characters. */
    private static Set<String> splitVowelConsonant(String term) {
        Set<String> parts = new Set<String>();
        String vowels = 'aeiou';
        if (term.length() < 8) {
            return parts;
        }
        for (Integer i = 2; i < term.length() - 1; i++) {
            Boolean prevIsVowel = vowels.contains(term.substring(i - 1, i));
            Boolean currIsVowel = vowels.contains(term.substring(i, i + 1));
            if (prevIsVowel && !currIsVowel) {
                String left = term.substring(0, i);
                String right = term.substring(i);
                if (left.length() >= 4 && right.length() >= 4) {
                    parts.add(left);
                    parts.add(right);
                }
            }
        }
        return parts;
    }

    /** 1 for identical strings down to 0 for completely different ones (Levenshtein distance over the longer length). */
    public static Double levenshteinSimilarity(String s1, String s2) {
        if (String.isBlank(s1) || String.isBlank(s2)) {
            return 0;
        }
        Integer maxLen = Math.max(s1.length(), s2.length());
        return 1.0 - ((Double) levenshteinDistance(s1, s2) / maxLen);
    }

    private static Integer levenshteinDistance(String s1, String s2) {
        Integer len1 = s1.length();
        Integer len2 = s2.length();
        List<Integer> prev = new List<Integer>();
        for (Integer j = 0; j <= len2; j++) { prev.add(j); }
        for (Integer i = 1; i <= len1; i++) {
            List<Integer> curr = new List<Integer>{ i };
            for (Integer j = 1; j <= len2; j++) {
                Integer cost = (s1.substring(i - 1, i) == s2.substring(j - 1, j)) ? 0 : 1;
                curr.add(Math.min(Math.min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost));
            }
            prev = curr;
        }
        return prev[len2];
    }

    public static Set<String> pluralSingularVariants(String word) {
        Set<String> variants = new Set<String>();
        if (String.isBlank(word) || word.length() < 2) {
            return variants;
        }
        // To plural
        if (word.endsWith('y') && !word.endsWith('ay') && !word.endsWith('ey')
            && !word.endsWith('oy') && !word.endsWith('uy')) {
            variants.add(word.substring(0, word.length() - 1) + 'ies');
        } else if (word.endsWith('s') || word.endsWith('x') || word.endsWith('z')
            || word.endsWith('ch') || word.endsWith('sh')) {
            variants.add(word + 'es');
        } else if (!word.endsWith('s')) {
            variants.add(word + 's');
        }
        // To singular
        if (word.endsWith('ies') && word.length() > 4) {
            variants.add(word.substring(0, word.length() - 3) + 'y');
        }
        if (word.endsWith('ses') || word.endsWith('xes') || word.endsWith('zes')
            || word.endsWith('ches') || word.endsWith('shes')) {
            variants.add(word.substring(0, word.length() - 2));
        } else if (word.endsWith('es') && word.length() > 3) {
            variants.add(word.substring(0, word.length() - 2));
        }
        if (word.endsWith('s') && !word.endsWith('ss') && word.length() > 2) {
            variants.add(word.substring(0, word.length() - 1));
        }
        return variants;
    }

    private static Boolean containsAny(Set<String> haystack, Set<String> candidates) {
        for (String candidate : candidates) {
            if (haystack.contains(candidate)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isUpper(String c) {
        return c.equals(c.toUpperCase()) && !c.equals(c.toLowerCase());
    }

    private static Boolean isLower(String c) {
        return c.equals(c.toLowerCase()) && !c.equals(c.toUpperCase());
    }
}
