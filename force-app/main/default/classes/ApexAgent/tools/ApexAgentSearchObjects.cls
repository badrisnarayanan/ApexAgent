/**
 * Apex Action tool: fuzzy-matches a search term against object API names/labels.
 *
 * Not bulk-mergeable: each input carries an independent search term with no
 * shared key to group on. ApexAgentToolExecutor only ever invokes this action
 * with a single input.
 */
public with sharing class ApexAgentSearchObjects {

    private static final Integer MAX_RESULTS = 10;

    // The most rows one EntityDefinition query returns
    @TestVisible
    private static Integer candidateLimit = 200;

    public class Input {
        @InvocableVariable(required=true label='Search Term' description='The term to fuzzy-match against Salesforce object API names and labels.')
        public String searchTerm;
    }

    public class Output {
        @InvocableVariable(label='Results' description='Matching objects ranked by relevance, best match first.')
        public List<ObjectMatch> results;
    }

    public class ObjectMatch {
        @InvocableVariable(label='Qualified API Name' description='API name of the object.')
        public String qualifiedApiName;

        @InvocableVariable(label='Label' description='Label of the object.')
        public String label;

        @InvocableVariable(label='Score' description='Relevance score; higher is a closer match.')
        public Double score;
    }

    @InvocableMethod(label='Search Objects' description='Searches for Salesforce objects that closely match a given term.\nUsage:\n- Use when the user provides an unfamiliar or ambiguous object name.\n- If multiple searches return no results, assume the object does not exist or is inaccessible to the user.')
    public static List<Output> run(List<Input> inputs) {
        try {
            List<Output> results = new List<Output>();
            for (Input inp : inputs) {
                results.add(processOne(inp));
            }
            return results;
        } catch (Exception e) {
            ApexAgentToolErrorContext.record(e);
            throw e;
        }
    }

    private static Output processOne(Input inp) {
        String searchTerm = ApexAgentToolInput.requireNotBlank(inp.searchTerm, 'searchTerm');

        Set<String> patterns = generatePatterns(searchTerm);
        Map<String, EntityDefinition> resultMap = queryEntities(patterns);
        Output o = new Output();
        o.results = scoreAndRank(resultMap, searchTerm);
        return o;
    }

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

    private static Set<String> generatePatterns(String searchTerm) {
        Set<String> patterns = new Set<String>();
        String lower = searchTerm.toLowerCase().trim();

        patterns.add(lower);

        // Abbreviation expansion
        if (ABBREVIATIONS.containsKey(lower)) {
            patterns.add(ABBREVIATIONS.get(lower));
        }

        // Split compound words by multiple strategies
        List<String> words = ApexAgentTextMatch.splitCompound(searchTerm);

        // Add each individual word + singular/plural
        for (String word : words) {
            String w = word.toLowerCase();
            patterns.add(w);
            patterns.addAll(ApexAgentTextMatch.pluralSingularVariants(w));

            // Check abbreviations for each word
            if (ABBREVIATIONS.containsKey(w)) {
                String expanded = ABBREVIATIONS.get(w);
                patterns.add(expanded);
                patterns.addAll(ApexAgentTextMatch.pluralSingularVariants(expanded));
            }
        }

        // Singular/plural of full term
        patterns.addAll(ApexAgentTextMatch.pluralSingularVariants(lower));

        // Join variants: remove spaces/underscores, swap spaces<->underscores
        String noSpaces = lower.replaceAll('[\\s_]', '');
        patterns.add(noSpaces);
        patterns.addAll(ApexAgentTextMatch.pluralSingularVariants(noSpaces));

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
            patterns.addAll(ApexAgentTextMatch.pluralSingularVariants(joined));

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

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static Map<String, EntityDefinition> queryEntities(Set<String> patterns) {
        Map<String, EntityDefinition> resultMap = new Map<String, EntityDefinition>();

        List<String> exactNames = new List<String>();
        List<String> likePatterns = new List<String>();
        for (String p : patterns) {
            exactNames.add(p);
            exactNames.add(p + '__c');
            likePatterns.add('%' + p + '%');
        }

        List<EntityDefinition> byApiName = [
            SELECT QualifiedApiName, Label
            FROM EntityDefinition
            WHERE IsCustomizable = true
            AND QualifiedApiName LIKE :likePatterns
            LIMIT :candidateLimit
        ];
        List<EntityDefinition> byLabel = [
            SELECT QualifiedApiName, Label
            FROM EntityDefinition
            WHERE IsCustomizable = true
            AND Label LIKE :likePatterns
            LIMIT :candidateLimit
        ];
        collect(resultMap, byApiName);
        collect(resultMap, byLabel);

        // A query that came back full was cut short in no particular order, which happens
        // in orgs with many custom or packaged objects. The object the term names outright
        // could be among the rows left out, so it is fetched on its own. LIKE with no %
        // matches the whole name, ignoring case.
        if (byApiName.size() == candidateLimit) {
            collect(resultMap, [
                SELECT QualifiedApiName, Label
                FROM EntityDefinition
                WHERE IsCustomizable = true
                AND QualifiedApiName LIKE :exactNames
                LIMIT 200
            ]);
        }
        if (byLabel.size() == candidateLimit) {
            collect(resultMap, [
                SELECT QualifiedApiName, Label
                FROM EntityDefinition
                WHERE IsCustomizable = true
                AND Label LIKE :exactNames
                LIMIT 200
            ]);
        }

        return resultMap;
    }

    private static void collect(Map<String, EntityDefinition> resultMap, List<EntityDefinition> entities) {
        for (EntityDefinition e : entities) {
            resultMap.put(e.QualifiedApiName, e);
        }
    }

    @TestVisible
    private static List<ObjectMatch> scoreAndRank(Map<String, EntityDefinition> resultMap, String searchTerm) {
        String lowerSearch = searchTerm.toLowerCase();
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

            // Word overlap — the search term's words against the API name's and label's words
            // (camelCase parts included; the __c-style suffix is not a word)
            Set<String> entityWordSet = ApexAgentTextMatch.wordSet(entity.QualifiedApiName.replaceFirst('__[A-Za-z]+$', ''));
            entityWordSet.addAll(ApexAgentTextMatch.wordSet(entity.Label));
            score += 40 * ApexAgentTextMatch.wordOverlap(searchTerm, entityWordSet);

            // Levenshtein similarity on the cleaned names
            Double apiSimilarity = ApexAgentTextMatch.levenshteinSimilarity(searchNoSeparators, apiNameClean);
            Double labelSimilarity = ApexAgentTextMatch.levenshteinSimilarity(lowerSearch, label);
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

        List<ObjectMatch> results = new List<ObjectMatch>();
        for (Integer i = 0; i < Math.min(MAX_RESULTS, scored.size()); i++) {
            ScoredEntity se = scored[i];
            ObjectMatch match = new ObjectMatch();
            match.qualifiedApiName = se.entity.QualifiedApiName;
            match.label            = se.entity.Label;
            match.score            = se.score;
            results.add(match);
        }
        return results;
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

            // Equal scores happen when a custom or packaged object is labelled like a
            // standard one. Standard objects go first, then the org's own, then packaged
            // ones, then the shorter name, so the order is the same on every call.
            String name = this.entity.QualifiedApiName;
            String otherName = o.entity.QualifiedApiName;
            if (origin(name) != origin(otherName)) {
                return origin(name) - origin(otherName);
            }
            if (name.length() != otherName.length()) {
                return name.length() - otherName.length();
            }
            return name.compareTo(otherName);
        }

        /** 0 standard (Account), 1 the org's own (Plan__c), 2 packaged (ns__Plan__c). */
        private Integer origin(String apiName) {
            return Math.min(apiName.countMatches('__'), 2);
        }
    }
}
