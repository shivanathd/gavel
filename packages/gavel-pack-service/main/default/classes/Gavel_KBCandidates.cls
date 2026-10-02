/**
 * Runtime options for Gavel_KB_Coverage (SVC-001.3): top N (default 20, max 50) online Knowledge articles from
 * SOSL on the case subject, plus "none". Title and Summary only, each Summary capped at 2,000 characters.
 * Knowledge not enabled -> SKIP knowledge_not_enabled. No candidates -> SKIP no_kb_candidates (a gap).
 */
public with sharing class Gavel_KBCandidates implements Gavel_OptionSource {
    public static final Integer DEFAULT_TOP = 20;
    public static final Integer MAX_TOP = 50;
    public static final String NONE = 'none';

    /** Test seam: candidates to use instead of SOSL. */
    @TestVisible
    private static List<Gavel_Option> testCandidates;
    @TestVisible
    private static Integer top = DEFAULT_TOP;

    public List<Gavel_Option> options(Id recordId, Gavel_Definition def, Gavel_Question question, Map<String, Object> state) {
        List<Gavel_Option> candidates = testCandidates != null ? testCandidates : search(state);
        if (candidates.isEmpty()) {
            throw new Gavel_SkipException('no_kb_candidates');
        }
        List<Gavel_Option> opts = new List<Gavel_Option>();
        for (Gavel_Option o : candidates) {
            if (opts.size() >= Math.min(MAX_TOP, top)) {
                break;
            }
            opts.add(o);
        }
        Gavel_Option noneOption = new Gavel_Option(NONE, 'None of these');
        noneOption.description = 'No candidate article answers the customer question.';
        opts.add(noneOption);
        return opts;
    }

    private static List<Gavel_Option> search(Map<String, Object> state) {
        if (!Schema.getGlobalDescribe().containsKey('knowledge__kav')) {
            throw new Gavel_SkipException('knowledge_not_enabled');
        }
        String subject = state == null ? null : (String) state.get('subject');
        String term = subject == null ? '' : subject.replaceAll('[^\\p{L}\\p{N} ]', ' ').normalizeSpace().left(100);
        if (term.length() < 2) {
            return new List<Gavel_Option>();
        }
        Integer n = Math.min(MAX_TOP, top);
        String sosl = 'FIND \'' + String.escapeSingleQuotes(term) + '\' IN ALL FIELDS RETURNING Knowledge__kav(Id, Title, Summary ' +
            'WHERE PublishStatus = \'Online\') LIMIT ' + n;
        List<Gavel_Option> result = new List<Gavel_Option>();
        List<List<SObject>> found;
        try {
            found = Search.query(sosl, AccessLevel.USER_MODE);
        } catch (Exception e) {
            // For example the running user is not a Knowledge user: no candidates can be read.
            throw new Gavel_SkipException('knowledge_unavailable');
        }
        for (SObject a : found[0]) {
            Gavel_Option o = new Gavel_Option(String.valueOf(a.Id), ((String) a.get('Title')).abbreviate(255));
            String summary = (String) a.get('Summary');
            o.description = summary == null ? null : summary.left(2000);
            result.add(o);
        }
        return result;
    }
}
