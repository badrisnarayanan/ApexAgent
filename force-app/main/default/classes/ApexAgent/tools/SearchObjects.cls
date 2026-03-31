public with sharing class SearchObjects implements ApexAgentTool {

    private static final Integer MAX_RESULTS = 10;

    private static final Map<String, String> ABBREVIATIONS = new Map<String, String>{
        'acc' => 'account',
        'acct' => 'account',
        'opp' => 'opportunity',
        'opps' => 'opportunity',
        'oppty' => 'opportunity',
        'cont' => 'contact',
        'cntct' => 'contact',
        'prod' => 'product',
        'prd' => 'product',
        'ord' => 'order',
        'inv' => 'invoice',
        'cat' => 'category',
        'org' => 'organization',
        'dept' => 'department',
        'mgr' => 'manager',
        'addr' => 'address',
        'desc' => 'description',
        'qty' => 'quantity',
        'amt' => 'amount',
        'usr' => 'user',
        'grp' => 'group',
        'msg' => 'message',
        'req' => 'request',
        'res' => 'response',
        'cfg' => 'configuration',
        'config' => 'configuration',
        'perm' => 'permission',
        'svc' => 'service',
        'srvc' => 'service',
        'loc' => 'location',
        'appt' => 'appointment',
        'sched' => 'schedule',
        'notif' => 'notification',
        'sub' => 'subscription',
        'txn' => 'transaction',
        'trans' => 'transaction',
        'proj' => 'project',
        'cust' => 'customer',
        'emp' => 'employee',
        'mgmt' => 'management',
        'rpt' => 'report',
        'doc' => 'document',
        'info' => 'information',
        'auth' => 'authorization',
        'cert' => 'certificate',
        'eval' => 'evaluation',
        'ref' => 'reference',
        'attch' => 'attachment',
        'atch' => 'attachment',
        'ent' => 'entitlement',
        'sol' => 'solution',
        'km' => 'knowledge',
        'kb' => 'knowledge',
        'wo' => 'workorder',
        'woli' => 'workorderlineitem',
        'sa' => 'serviceappointment',
        'sr' => 'servicereport',
        'st' => 'serviceresource',
        'cmpgn' => 'campaign',
        'cmpn' => 'campaign',
        'ld' => 'lead',
        'tsk' => 'task',
        'evt' => 'event',
        'ast' => 'asset',
        'cse' => 'case',
        'soln' => 'solution',
        'ctrct' => 'contract'
    };

    public Object execute(Map<String, Object> input) {
        if (input == null || !input.containsKey('searchTerm')) {
            throw new IllegalArgumentException('Missing required input parameter: searchTerm');
        }
        Object rawTerm = input.get('searchTerm');
        if (rawTerm == null) {
            throw new IllegalArgumentException('Input parameter searchTerm must not be null');
        }
        String searchTerm = String.valueOf(rawTerm).trim();
        if (String.isBlank(searchTerm)) {
            throw new IllegalArgumentException('Input parameter searchTerm must not be blank');
        }
        searchTerm = searchTerm.trim();

        Set<String> patterns = generatePatterns(searchTerm);
        System.debug('Generated ' + patterns.size() + ' patterns for: ' + searchTerm);
        System.debug('Patterns: ' + patterns);

        Map<String, EntityDefinition> resultMap = queryEntities(patterns);
        System.debug('Found ' + resultMap.size() + ' unique entities');

        List<Map<String, Object>> scored = scoreAndRank(resultMap, searchTerm);
        System.debug('Top results for "' + searchTerm + '":');
        for (Map<String, Object> r : scored) {
            System.debug('  ' + r.get('QualifiedApiName') + ' (' + r.get('Label') + ') score=' + r.get('score'));
        }
        return scored;
    }

    private Set<String> generatePatterns(String searchTerm) {
        Set<String> patterns = new Set<String>();
        String lower = searchTerm.toLowerCase().trim();

        patterns.add(lower);

        // Abbreviation expansion
        if (ABBREVIATIONS.containsKey(lower)) {
            patterns.add(ABBREVIATIONS.get(lower));
        }

        // Split compound words by multiple strategies
        List<String> words = splitCompound(searchTerm);
        System.debug('Split words: ' + words);

        // Add each individual word + singular/plural
        for (String word : words) {
            String w = word.toLowerCase();
            patterns.add(w);
            patterns.addAll(pluralSingularVariants(w));

            // Check abbreviations for each word
            if (ABBREVIATIONS.containsKey(w)) {
                String expanded = ABBREVIATIONS.get(w);
                patterns.add(expanded);
                patterns.addAll(pluralSingularVariants(expanded));
            }
        }

        // Singular/plural of full term
        patterns.addAll(pluralSingularVariants(lower));

        // Join variants: remove spaces/underscores, swap spaces<->underscores
        String noSpaces = lower.replaceAll('[\\s_]', '');
        patterns.add(noSpaces);
        patterns.addAll(pluralSingularVariants(noSpaces));

        String withUnderscores = lower.replaceAll('\\s+', '_');
        patterns.add(withUnderscores);

        String withSpaces = lower.replaceAll('_', ' ');
        patterns.add(withSpaces);

        // Concatenate words without separator
        if (words.size() > 1) {
            String joined = '';
            for (String w : words) {
                joined += w.toLowerCase();
            }
            patterns.add(joined);
            patterns.addAll(pluralSingularVariants(joined));

            // Also try underscore-joined
            patterns.add(String.join(words, '_').toLowerCase());

            // First-letter abbreviation
            String abbrev = '';
            for (String w : words) {
                if (w.length() > 0) {
                    abbrev += w.substring(0, 1).toLowerCase();
                }
            }
            if (abbrev.length() > 1) {
                patterns.add(abbrev);
                if (ABBREVIATIONS.containsKey(abbrev)) {
                    patterns.add(ABBREVIATIONS.get(abbrev));
                }
            }
        }

        // Remove empty/tiny strings and self-duplications
        patterns.remove('');
        Set<String> cleaned = new Set<String>();
        for (String p : patterns) {
            if (p.length() >= 2 && !p.contains(lower + lower)) {
                cleaned.add(p);
            }
        }
        return cleaned;
    }

    private List<String> splitCompound(String term) {
        Set<String> wordSet = new Set<String>();

        // Split by spaces and underscores first
        for (String part : term.split('[\\s_]+')) {
            if (String.isNotBlank(part)) {
                wordSet.add(part.toLowerCase());
                // Further split by camelCase
                wordSet.addAll(splitCamelCase(part));
            }
        }

        // Split by doubled consonants (e.g., "mapping" -> "map", "ping")
        String lower = term.toLowerCase().replaceAll('[\\s_]', '');
        wordSet.addAll(splitDoubledConsonants(lower));

        // Split by vowel-consonant boundary patterns
        wordSet.addAll(splitVowelConsonant(lower));

        // Remove blanks
        wordSet.remove('');

        return new List<String>(wordSet);
    }

    private List<String> splitCamelCase(String term) {
        List<String> words = new List<String>();
        String current = '';

        for (Integer i = 0; i < term.length(); i++) {
            String ch = term.substring(i, i + 1);

            if (i > 0 && ch == ch.toUpperCase() && ch != ch.toLowerCase()) {
                // Uppercase letter found — check if it's start of a new word
                if (String.isNotBlank(current)) {
                    words.add(current.toLowerCase());
                }
                current = ch;
            } else {
                current += ch;
            }
        }
        if (String.isNotBlank(current)) {
            words.add(current.toLowerCase());
        }
        return words;
    }

    private Set<String> splitDoubledConsonants(String term) {
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

    private Set<String> splitVowelConsonant(String term) {
        Set<String> parts = new Set<String>();
        String vowels = 'aeiou';

        // Only attempt vowel-consonant splitting on longer terms
        if (term.length() < 8) {
            return parts;
        }

        for (Integer i = 2; i < term.length() - 1; i++) {
            String prev = term.substring(i - 1, i);
            String curr = term.substring(i, i + 1);
            Boolean prevIsVowel = vowels.contains(prev);
            Boolean currIsVowel = vowels.contains(curr);

            // Split at vowel->consonant boundary when both halves are substantial
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

    private Set<String> pluralSingularVariants(String word) {
        Set<String> variants = new Set<String>();
        if (String.isBlank(word) || word.length() < 2) {
            return variants;
        }

        // To plural
        if (word.endsWith('y') && !word.endsWith('ay') && !word.endsWith('ey') && !word.endsWith('oy') && !word.endsWith('uy')) {
            variants.add(word.substring(0, word.length() - 1) + 'ies');
        } else if (word.endsWith('s') || word.endsWith('x') || word.endsWith('z') || word.endsWith('ch') || word.endsWith('sh')) {
            variants.add(word + 'es');
        } else if (!word.endsWith('s')) {
            variants.add(word + 's');
        }

        // To singular
        if (word.endsWith('ies') && word.length() > 4) {
            variants.add(word.substring(0, word.length() - 3) + 'y');
        }
        if (word.endsWith('ses') || word.endsWith('xes') || word.endsWith('zes') || word.endsWith('ches') || word.endsWith('shes')) {
            variants.add(word.substring(0, word.length() - 2));
        } else if (word.endsWith('es') && word.length() > 3) {
            variants.add(word.substring(0, word.length() - 2));
        }
        if (word.endsWith('s') && !word.endsWith('ss') && word.length() > 2) {
            variants.add(word.substring(0, word.length() - 1));
        }

        return variants;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private Map<String, EntityDefinition> queryEntities(Set<String> patterns) {
        Map<String, EntityDefinition> resultMap = new Map<String, EntityDefinition>();

        List<String> likePatterns = new List<String>();
        for (String p : patterns) {
            likePatterns.add('%' + p + '%');
        }

        for (EntityDefinition e : [
            SELECT QualifiedApiName, Label
            FROM EntityDefinition
            WHERE IsCustomizable = true
            AND QualifiedApiName LIKE :likePatterns
            LIMIT 200
        ]) {
            resultMap.put(e.QualifiedApiName, e);
        }

        for (EntityDefinition e : [
            SELECT QualifiedApiName, Label
            FROM EntityDefinition
            WHERE IsCustomizable = true
            AND Label LIKE :likePatterns
            LIMIT 200
        ]) {
            if (!resultMap.containsKey(e.QualifiedApiName)) {
                resultMap.put(e.QualifiedApiName, e);
            }
        }

        return resultMap;
    }

    private List<Map<String, Object>> scoreAndRank(Map<String, EntityDefinition> resultMap, String searchTerm) {
        String lowerSearch = searchTerm.toLowerCase();
        List<String> searchWords = splitCompound(searchTerm);
        String searchNoSeparators = lowerSearch.replaceAll('[\\s_]', '');

        List<ScoredEntity> scored = new List<ScoredEntity>();

        for (EntityDefinition entity : resultMap.values()) {
            String apiName = entity.QualifiedApiName.toLowerCase();
            String label = (entity.Label != null) ? entity.Label.toLowerCase() : apiName;
            String apiNameClean = apiName.replaceAll('[_]', '');

            Double score = 0;

            // Exact match
            if (apiName == lowerSearch || label == lowerSearch || apiNameClean == searchNoSeparators) {
                score += 100;
            }

            // Starts-with match
            if (apiName.startsWith(lowerSearch) || label.startsWith(lowerSearch) ||
                apiNameClean.startsWith(searchNoSeparators)) {
                score += 60;
            }

            // Contains match
            if (apiName.contains(lowerSearch) || label.contains(lowerSearch) ||
                apiNameClean.contains(searchNoSeparators)) {
                score += 30;
            }

            // Word overlap scoring — lightweight split for entity names (camelCase + underscores only)
            Set<String> entityWordSet = new Set<String>();
            for (String w : splitCamelCase(apiName.replaceAll('_', ''))) {
                entityWordSet.add(w);
            }
            if (entity.Label != null) {
                for (String w : label.split('\\s+')) {
                    entityWordSet.add(w);
                }
            }
            Integer matchedWords = 0;
            for (String sw : searchWords) {
                String swLower = sw.toLowerCase();
                if (entityWordSet.contains(swLower)) {
                    matchedWords++;
                } else {
                    // Check plural/singular variants
                    Set<String> variants = pluralSingularVariants(swLower);
                    for (String v : variants) {
                        if (entityWordSet.contains(v)) {
                            matchedWords++;
                            break;
                        }
                    }
                }
            }
            if (!searchWords.isEmpty()) {
                score += 40 * ((Double) matchedWords / searchWords.size());
            }

            // Levenshtein similarity on the cleaned names
            Double apiSimilarity = levenshteinSimilarity(searchNoSeparators, apiNameClean);
            Double labelSimilarity = levenshteinSimilarity(lowerSearch, label);
            score += 20 * Math.max(apiSimilarity, labelSimilarity);

            // Abbreviation match bonus
            if (ABBREVIATIONS.containsKey(lowerSearch)) {
                String expanded = ABBREVIATIONS.get(lowerSearch);
                if (apiName.contains(expanded) || label.contains(expanded)) {
                    score += 50;
                }
            }

            // Length penalty — prefer shorter/more precise names
            if (apiName.length() > 40) {
                score -= 5;
            }

            if (score > 0) {
                scored.add(new ScoredEntity(entity, score));
            }
        }

        scored.sort();

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Integer i = 0; i < Math.min(MAX_RESULTS, scored.size()); i++) {
            ScoredEntity se = scored[i];
            results.add(new Map<String, Object>{
                'QualifiedApiName' => se.entity.QualifiedApiName,
                'Label' => se.entity.Label,
                'score' => se.score
            });
        }
        return results;
    }

    private Double levenshteinSimilarity(String s1, String s2) {
        if (String.isBlank(s1) || String.isBlank(s2)) {
            return 0;
        }
        Integer maxLen = Math.max(s1.length(), s2.length());
        if (maxLen == 0) {
            return 1;
        }
        Integer dist = levenshteinDistance(s1, s2);
        return 1.0 - ((Double) dist / maxLen);
    }

    private Integer levenshteinDistance(String s1, String s2) {
        Integer len1 = s1.length();
        Integer len2 = s2.length();

        // Use single-row optimization
        List<Integer> prev = new List<Integer>();
        for (Integer j = 0; j <= len2; j++) {
            prev.add(j);
        }

        for (Integer i = 1; i <= len1; i++) {
            List<Integer> curr = new List<Integer>();
            curr.add(i);
            for (Integer j = 1; j <= len2; j++) {
                Integer cost = (s1.substring(i - 1, i) == s2.substring(j - 1, j)) ? 0 : 1;
                Integer insert_op = curr[j - 1] + 1;
                Integer delete_op = prev[j] + 1;
                Integer replace_op = prev[j - 1] + cost;
                curr.add(Math.min(Math.min(insert_op, delete_op), replace_op));
            }
            prev = curr;
        }
        return prev[len2];
    }

    private class ScoredEntity implements Comparable {
        public EntityDefinition entity;
        public Double score;

        public ScoredEntity(EntityDefinition entity, Double score) {
            this.entity = entity;
            this.score = score;
        }

        public Integer compareTo(Object other) {
            ScoredEntity o = (ScoredEntity) other;
            // Descending order
            if (this.score > o.score) return -1;
            if (this.score < o.score) return 1;
            return 0;
        }
    }
}
