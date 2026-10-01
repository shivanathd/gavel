/**
 * KB coverage and gap detection (SVC-001.3). Runs Gavel_KB_Coverage and records a Gavel_KB_Gap__c when no
 * candidate exists, the answer is "none", or the article does not answer the question. Gaps are Gavel records,
 * so they are created in Shadow too; no Case field changes.
 */
public with sharing class Gavel_KBCoverage {
    public static final String DEFINITION = 'Gavel_KB_Coverage';

    public class Request {
        @InvocableVariable(label='Case Id' required=true)
        public Id caseId;
    }

    public class Result {
        @InvocableVariable(label='Outcome')
        public String outcome;
        @InvocableVariable(label='Article Id' description='Best article, or none')
        public String articleId;
        @InvocableVariable(label='Gap Created')
        public Boolean gapCreated = false;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
    }

    @InvocableMethod(label='Gavel: Check KB Coverage' description='Finds the Knowledge article that answers a case, or records a KB gap.' category='Gavel' callout=true)
    public static List<Result> invoke(List<Request> requests) {
        List<Id> ids = new List<Id>();
        for (Request r : requests == null ? new List<Request>() : requests) {
            ids.add(r.caseId);
        }
        return check(ids);
    }

    public static List<Result> check(List<Id> caseIds) {
        List<Result> out = new List<Result>();
        List<Gavel_Runtime.RunRequest> runs = new List<Gavel_Runtime.RunRequest>();
        for (Id cid : caseIds) {
            runs.add(new Gavel_Runtime.RunRequest(cid, DEFINITION));
        }
        List<Gavel_Runtime.RunResult> results = Gavel_Runtime.runAll(runs);
        List<Gavel_KB_Gap__c> gaps = new List<Gavel_KB_Gap__c>();
        Map<Id, Case> cases = new Map<Id, Case>([SELECT Id, Subject, Description FROM Case WHERE Id IN :caseIds WITH USER_MODE]);
        for (Integer i = 0; i < results.size(); i++) {
            Gavel_Runtime.RunResult res = results[i];
            Result r = new Result();
            r.outcome = res.outcome;
            r.ledgerId = res.ledgerId;
            r.articleId = res.answerValues.get('article');
            Boolean noCandidates = res.outcome == Gavel_Outcome.SKIP && res.reason == 'no_kb_candidates';
            String answers = res.perQuestion.get('answers_question');
            Boolean weak = res.answerValues.get('answers_question') == 'false' || (answers != null && answers.startsWith(Gavel_Outcome.ESCALATE));
            Boolean judged = res.outcome != Gavel_Outcome.SKIP && res.outcome != Gavel_Outcome.ERROR;
            if (noCandidates || (judged && (r.articleId == Gavel_KBCandidates.NONE || weak))) {
                Case c = cases.get(caseIds[i]);
                gaps.add(new Gavel_KB_Gap__c(
                    Case__c = caseIds[i],
                    Decision_Log__c = res.ledgerId,
                    Question_Text__c = c == null ? null : questionText(c),
                    Top_Candidates__c = topCandidates(res.answersJson),
                    Status__c = 'New'
                ));
                r.gapCreated = true;
            }
            out.add(r);
        }
        if (!gaps.isEmpty()) {
            insert gaps;
        }
        return out;
    }

    /** Redacted with the strict profile: the gap record must not become a PII copy. */
    private static String questionText(Case c) {
        String text = (c.Subject == null ? '' : c.Subject) + (c.Description == null ? '' : '\n' + c.Description);
        return Gavel_Redactor.redact(text, 'strict').text.left(2000);
    }

    /** Candidate article ids from the ledgered distribution, most likely first ("none" excluded). */
    private static String topCandidates(String answersJson) {
        if (String.isBlank(answersJson)) {
            return null;
        }
        try {
            Map<String, Object> doc = (Map<String, Object>) JSON.deserializeUntyped(answersJson);
            Map<String, Object> answers = (Map<String, Object>) doc.get('answers');
            Map<String, Object> article = answers == null ? null : (Map<String, Object>) answers.get('article');
            Map<String, Object> probs = article == null ? null : (Map<String, Object>) article.get('probabilities');
            if (probs == null) {
                return null;
            }
            List<Ranked> ranked = new List<Ranked>();
            for (String k : probs.keySet()) {
                if (k != Gavel_KBCandidates.NONE) {
                    Object v = probs.get(k);
                    ranked.add(new Ranked(k, v == null ? null : Decimal.valueOf(String.valueOf(v))));
                }
            }
            ranked.sort();
            List<String> ids = new List<String>();
            for (Ranked rk : ranked) {
                ids.add(rk.key);
            }
            return String.join(ids, ',').left(5000);
        } catch (Exception e) {
            return null;
        }
    }

    private class Ranked implements Comparable {
        public String key;
        public Decimal p;

        public Ranked(String key, Decimal p) {
            this.key = key;
            this.p = p == null ? 0 : p;
        }

        public Integer compareTo(Object other) {
            Ranked o = (Ranked) other;
            if (p == o.p) {
                return key.compareTo(o.key);
            }
            return p > o.p ? -1 : 1;
        }
    }
}
