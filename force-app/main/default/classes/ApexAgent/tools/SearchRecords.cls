public with sharing class SearchRecords implements ApexAgentTool {

    private static final Integer SOSL_LIMIT = 50;
    private static final Integer MAX_RESULTS = 25;

    private static final Set<String> COMPANY_SUFFIXES = new Set<String>{
        'inc', 'llc', 'ltd', 'corp', 'co', 'group', 'holdings', 'limited',
        'plc', 'gmbh', 'ag', 'sa', 'nv', 'bv', 'pty', 'pvt', 'srl', 'sas'
    };

    private static final Map<String, String> ABBREVIATIONS = new Map<String, String>{
        'acc'   => 'account',   'acct'  => 'account',
        'opp'   => 'opportunity','opps' => 'opportunity','oppty' => 'opportunity',
        'cont'  => 'contact',   'cntct' => 'contact',
        'prod'  => 'product',   'prd'   => 'product',
        'ord'   => 'order',     'inv'   => 'invoice',
        'org'   => 'organization','dept' => 'department',
        'mgr'   => 'manager',   'addr'  => 'address',
        'qty'   => 'quantity',  'amt'   => 'amount',
        'usr'   => 'user',      'grp'   => 'group',
        'req'   => 'request',   'res'   => 'response',
        'cfg'   => 'configuration','config' => 'configuration',
        'perm'  => 'permission','svc'   => 'service',
        'cust'  => 'customer',  'emp'   => 'employee',
        'proj'  => 'project',   'mgmt'  => 'management',
        'doc'   => 'document',  'auth'  => 'authorization',
        'ref'   => 'reference', 'ld'    => 'lead',
        'cse'   => 'case',      'ast'   => 'asset',
        'cmpgn' => 'campaign',  'tsk'   => 'task'
    };

    // ─── Entry point ────────────────────────────────────────────────────────────

    public Object execute(Map<String, Object> input) {
        if (input == null) {
            throw new IllegalArgumentException('Input map must not be null');
        }
        if (!input.containsKey('searchTerm')) {
            throw new IllegalArgumentException('Missing required input parameter: searchTerm');
        }
        if (!input.containsKey('objectApiName')) {
            throw new IllegalArgumentException('Missing required input parameter: objectApiName');
        }

        Object rawTerm = input.get('searchTerm');
        Object rawObject = input.get('objectApiName');

        if (rawTerm == null) {
            throw new IllegalArgumentException('Input parameter searchTerm must not be null');
        }
        if (rawObject == null) {
            throw new IllegalArgumentException('Input parameter objectApiName must not be null');
        }

        String searchTerm = String.valueOf(rawTerm).trim();
        String objectApiName = String.valueOf(rawObject).trim();

        if (String.isBlank(searchTerm)) {
            throw new IllegalArgumentException('Input parameter searchTerm must not be blank');
        }
        if (String.isBlank(objectApiName)) {
            throw new IllegalArgumentException('Input parameter objectApiName must not be blank');
        }

        Schema.DescribeSObjectResult describe = ApexAgentUtils.getDescribe(objectApiName);
        if (!describe.isSearchable() || !describe.isAccessible()) {
            throw new IllegalArgumentException(
                'Object "' + objectApiName + '" is not searchable or not accessible by the current user'
            );
        }

        String soslClause = buildSoslClause(searchTerm);
        System.debug('SOSL clause: ' + soslClause);

        List<SObject> rawResults = executeSosl(soslClause, objectApiName);
        System.debug('SOSL returned ' + rawResults.size() + ' records');

        return scoreAndRank(rawResults, searchTerm);
    }

    // ─── SOSL execution ──────────────────────────────────────────────────────────

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private List<SObject> executeSosl(String soslClause, String objectApiName) {
        String query = 'FIND {' + soslClause + '} IN NAME FIELDS RETURNING '
            + objectApiName + '(Id, Name) LIMIT ' + SOSL_LIMIT;
        List<List<SObject>> results = Search.query(query);
        return results.isEmpty() ? new List<SObject>() : results[0];
    }

    // ─── SOSL clause builder ─────────────────────────────────────────────────────

    private String buildSoslClause(String searchTerm) {
        Set<String> variants = generateSoslVariants(searchTerm);

        // Wrap each variant in wildcards and escape SOSL reserved characters
        Set<String> soslTerms = new Set<String>();
        for (String v : variants) {
            if (String.isNotBlank(v) && v.length() >= 2) {
                soslTerms.add('*' + escapeSosl(v) + '*');
            }
        }

        // Always include the original term with wildcards as a safety net
        soslTerms.add('*' + escapeSosl(searchTerm.trim().toLowerCase()) + '*');

        return String.join(new List<String>(soslTerms), ' OR ');
    }

    private String escapeSosl(String term) {
        // Escape SOSL reserved characters: ? & | ! { } [ ] ( ) ^ ~ * : \ " ' + -
        return term
            .replace('\\', '\\\\')
            .replace('"',  '\\"')
            .replace('\'', '\\\'')
            .replace('&',  '\\&')
            .replace('|',  '\\|')
            .replace('!',  '\\!')
            .replace('^',  '\\^')
            .replace('~',  '\\~')
            .replace(':',  '\\:')
            .replace('+',  '\\+')
            .replace('-',  '\\-');
    }

    @SuppressWarnings('PMD.NcssMethodCount')
    private Set<String> generateSoslVariants(String searchTerm) {
        Set<String> variants = new Set<String>();
        String lower = searchTerm.toLowerCase().trim();

        variants.add(lower);

        // Abbreviation expansion
        if (ABBREVIATIONS.containsKey(lower)) {
            variants.add(ABBREVIATIONS.get(lower));
        }

        // Compound word splitting
        List<String> words = splitCompound(searchTerm);
        for (String word : words) {
            String w = word.toLowerCase();
            if (w.length() >= 2) {
                variants.add(w);
                variants.addAll(pluralSingularVariants(w));
                if (ABBREVIATIONS.containsKey(w)) {
                    String expanded = ABBREVIATIONS.get(w);
                    variants.add(expanded);
                    variants.addAll(pluralSingularVariants(expanded));
                }
            }
        }

        // Join variants
        String noSep = lower.replaceAll('[\\s_]', '');
        variants.add(noSep);
        variants.add(lower.replaceAll('\\s+', '_'));
        variants.add(lower.replaceAll('_', ' '));

        if (words.size() > 1) {
            String joined = '';
            for (String w : words) { joined += w.toLowerCase(); }
            variants.add(joined);
            variants.add(String.join(words, '_').toLowerCase());
        }

        // ── Person name handling ──────────────────────────────────────────────
        // If the search term looks like a name (contains a space)
        List<String> tokens = lower.split('\\s+');
        if (tokens.size() >= 2) {
            String firstName = tokens[0];
            String lastName  = tokens[tokens.size() - 1];

            variants.add(firstName);           // first name alone
            variants.add(lastName);            // last name alone
            variants.add(lastName + ' ' + firstName);  // transposed: "Smith John"

            // Initials variant: "J Smith"
            if (firstName.length() > 0) {
                variants.add(firstName.substring(0, 1) + ' ' + lastName);
            }

            // Multi-word last name (e.g. "de la Cruz")
            if (tokens.size() > 2) {
                String middlePart = '';
                for (Integer i = 1; i < tokens.size() - 1; i++) {
                    middlePart += tokens[i] + ' ';
                }
                variants.add(firstName + ' ' + middlePart.trim());
                variants.add(middlePart.trim() + ' ' + lastName);
            }
        }

        // ── Company name handling ─────────────────────────────────────────────
        // Strip common legal suffixes and search the clean name
        String cleanCompany = stripCompanySuffix(lower);
        if (cleanCompany != lower && cleanCompany.length() >= 2) {
            variants.add(cleanCompany);
            variants.addAll(pluralSingularVariants(cleanCompany));

            // Individual words of the clean company name
            for (String w : cleanCompany.split('\\s+')) {
                if (w.length() >= 2 && !COMPANY_SUFFIXES.contains(w)) {
                    variants.add(w);
                }
            }
        }

        // Individual words for any multi-word term
        if (tokens.size() >= 2) {
            for (String token : tokens) {
                if (token.length() >= 2 && !COMPANY_SUFFIXES.contains(token)) {
                    variants.add(token);
                }
            }
        }

        // Cleanup: remove blanks and length-1 strings
        Set<String> cleaned = new Set<String>();
        for (String v : variants) {
            if (String.isNotBlank(v) && v.length() >= 2) {
                cleaned.add(v);
            }
        }
        return cleaned;
    }

    private String stripCompanySuffix(String name) {
        List<String> tokens = name.split('\\s+');
        while (!tokens.isEmpty() && COMPANY_SUFFIXES.contains(tokens[tokens.size() - 1].replaceAll('[.,]', ''))) {
            tokens.remove(tokens.size() - 1);
        }
        return String.join(tokens, ' ').trim();
    }

    // ─── Scoring & ranking ───────────────────────────────────────────────────────

    private List<Map<String, Object>> scoreAndRank(List<SObject> records, String searchTerm) {
        String lowerSearch    = searchTerm.toLowerCase().trim();
        String cleanSearch    = stripCompanySuffix(lowerSearch);
        List<String> searchWords = splitCompound(searchTerm);

        // Person name parts
        List<String> nameTokens = lowerSearch.split('\\s+');
        String searchFirst = nameTokens.size() >= 2 ? nameTokens[0]                    : '';
        String searchLast  = nameTokens.size() >= 2 ? nameTokens[nameTokens.size() - 1] : '';

        List<ScoredRecord> scored = new List<ScoredRecord>();

        for (SObject record : records) {
            String name = (String) record.get('Name');
            if (String.isBlank(name)) {
                continue;
            }
            String lowerName  = name.toLowerCase();
            String cleanName  = stripCompanySuffix(lowerName);

            Double score = 0;

            // Exact match
            if (lowerName == lowerSearch || cleanName == cleanSearch) {
                score += 100;
            }

            // Starts-with
            if (lowerName.startsWith(lowerSearch) || cleanName.startsWith(cleanSearch)) {
                score += 60;
            }

            // Ends-with
            if (lowerName.endsWith(lowerSearch) || cleanName.endsWith(cleanSearch)) {
                score += 50;
            }

            // Contains
            if (lowerName.contains(lowerSearch) || cleanName.contains(cleanSearch)) {
                score += 30;
            }

            // Word overlap
            List<String> nameWords = lowerName.split('\\s+');
            Set<String> nameWordSet = new Set<String>(nameWords);
            Integer matchedWords = 0;
            for (String sw : searchWords) {
                String swLower = sw.toLowerCase();
                if (nameWordSet.contains(swLower)) {
                    matchedWords++;
                } else {
                    Set<String> variants = pluralSingularVariants(swLower);
                    for (String v : variants) {
                        if (nameWordSet.contains(v)) {
                            matchedWords++;
                            break;
                        }
                    }
                }
            }
            if (!searchWords.isEmpty()) {
                score += 40 * ((Double) matchedWords / searchWords.size());
            }

            // Levenshtein similarity
            Double sim = levenshteinSimilarity(lowerSearch, lowerName);
            score += 20 * sim;

            // Person name bonuses
            if (String.isNotBlank(searchFirst) && lowerName.contains(searchFirst)) {
                score += 15;
            }
            if (String.isNotBlank(searchLast) && lowerName.contains(searchLast)) {
                score += 15;
            }

            // Company: clean name bonus
            if (String.isNotBlank(cleanSearch) && cleanSearch != lowerSearch
                && (lowerName.contains(cleanSearch) || cleanName.contains(cleanSearch))) {
                score += 10;
            }

            // Length penalty
            if (name.length() > 50) {
                score -= 5;
            }

            if (score > 0) {
                scored.add(new ScoredRecord(record, name, score));
            }
        }

        scored.sort();

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Integer i = 0; i < Math.min(MAX_RESULTS, scored.size()); i++) {
            ScoredRecord sr = scored[i];
            results.add(new Map<String, Object>{
                'Id'    => sr.record.Id,
                'Name'  => sr.name,
                'score' => sr.score
            });
        }
        return results;
    }

    // ─── String splitting helpers ────────────────────────────────────────────────

    private List<String> splitCompound(String term) {
        Set<String> wordSet = new Set<String>();
        for (String part : term.split('[\\s_]+')) {
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

    private List<String> splitCamelCase(String term) {
        List<String> words = new List<String>();
        String current = '';
        for (Integer i = 0; i < term.length(); i++) {
            String ch = term.substring(i, i + 1);
            if (i > 0 && ch == ch.toUpperCase() && ch != ch.toLowerCase()) {
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

    private Set<String> pluralSingularVariants(String word) {
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

    // ─── Levenshtein ─────────────────────────────────────────────────────────────

    private Double levenshteinSimilarity(String s1, String s2) {
        if (String.isBlank(s1) || String.isBlank(s2)) {
            return 0;
        }
        Integer maxLen = Math.max(s1.length(), s2.length());
        if (maxLen == 0) {
            return 1;
        }
        return 1.0 - ((Double) levenshteinDistance(s1, s2) / maxLen);
    }

    private Integer levenshteinDistance(String s1, String s2) {
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

    // ─── Inner class ─────────────────────────────────────────────────────────────

    private class ScoredRecord implements Comparable {
        public SObject record;
        public String  name;
        public Double  score;

        public ScoredRecord(SObject record, String name, Double score) {
            this.record = record;
            this.name   = name;
            this.score  = score;
        }

        public Integer compareTo(Object other) {
            ScoredRecord o = (ScoredRecord) other;
            if (this.score > o.score) { return -1; }
            if (this.score < o.score) { return  1; }
            return 0;
        }
    }
}
