/**
 * Result of the policy engine for one run (F5, contracts/policy-contract.md).
 */
public with sharing class Gavel_Outcome {
    public static final String AUTO = 'AUTO';
    public static final String REVIEW = 'REVIEW';
    public static final String ESCALATE = 'ESCALATE';
    public static final String SKIP = 'SKIP';
    public static final String ERROR = 'ERROR';
    public static final String PENDING = 'PENDING';

    private static final Map<String, Integer> SEVERITY_RANK = new Map<String, Integer>{
        AUTO => 1, REVIEW => 2, ESCALATE => 3, SKIP => 4, ERROR => 5
    };

    public String outcome;
    public String reason;
    /** questionKey -> "OUTCOME:reason" */
    public Map<String, String> perQuestion = new Map<String, String>();
    public Map<String, QuestionResult> questions = new Map<String, QuestionResult>();
    public Boolean actionSuppressed = false;
    public String suppressReason;
    public String asymmetricReason;
    public String decidingQuestion;

    public class QuestionResult {
        public String key;
        public String questionType;
        public String outcome;
        public String reason;
        /** Answer value used by action maps: choice key, score value, or 'true'/'false' for noul. */
        public String answerValue;
        /** The number the policy compared (choice top probability, score confidence, noul action-side probability). */
        public Decimal policyValue;
        /** Value calibrated against labels: choice top probability, score confidence, noul certainty max(p, 1-p). */
        public Decimal calibrationValue;
        public Decimal margin;
        public Boolean participating = false;
    }

    public static Integer severity(String outcome) {
        return SEVERITY_RANK.containsKey(outcome) ? SEVERITY_RANK.get(outcome) : 5;
    }

    /** Most conservative of two outcomes: ERROR > SKIP > ESCALATE > REVIEW > AUTO (ADR-008). */
    public static String moreConservative(String a, String b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return severity(b) > severity(a) ? b : a;
    }

    public static Gavel_Outcome create(String outcome, String reason) {
        Gavel_Outcome o = new Gavel_Outcome();
        o.outcome = outcome;
        o.reason = reason;
        return o;
    }

    public Boolean isAuto() {
        return outcome == AUTO;
    }

    public Boolean needsReview() {
        return outcome == REVIEW || outcome == ESCALATE;
    }
}
