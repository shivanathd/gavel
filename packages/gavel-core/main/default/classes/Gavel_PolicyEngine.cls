/**
 * Turns a validated judgment into AUTO | REVIEW | ESCALATE | SKIP | ERROR (F5). Deterministic, fails closed.
 *
 * Choice (POL-001.1/.4/.5): non-ok status -> ERROR; null confidence -> REVIEW unknown_confidence;
 *   escape option wins -> REVIEW escape_selected; top < review_at -> ESCALATE; top >= auto_accept AND
 *   margin >= min_margin AND no tie -> AUTO; margin short -> REVIEW margin_below_min; else REVIEW.
 * Score (POL-001.2): on confidence, same bands; the score passes through unchanged.
 * Noul (POL-001.3): a = probability of the action side (Noul_Direction__c).
 *   a >= auto_accept -> AUTO (act); a <= min(review_at, 1 - auto_accept) -> AUTO with no action;
 *   a >= review_at -> REVIEW; otherwise ESCALATE.
 * Definition outcome = most conservative over Required_For_Action__c questions, or all questions if
 * none are required (POL-001.6). Shadow/Draft compute the outcome but suppress actions (POL-001.7).
 */
public with sharing class Gavel_PolicyEngine {
    public static final String R_ACCEPTED = 'accepted';
    public static final String R_ACCEPTED_NO_ACTION = 'accepted_no_action';
    public static final String R_UNKNOWN_CONFIDENCE = 'unknown_confidence';
    public static final String R_ESCAPE = 'escape_selected';
    public static final String R_MARGIN = 'margin_below_min';
    public static final String R_BELOW_AUTO = 'confidence_below_auto_accept';
    public static final String R_BELOW_REVIEW = 'confidence_below_review';
    public static final String R_POLICY_MISSING = 'policy_missing';
    public static final String R_INVALID_RESPONSE = 'invalid_response';
    public static final String SUPPRESS_SHADOW = 'action_suppressed_shadow';
    public static final String SUPPRESS_DRAFT = 'action_suppressed_draft';
    public static final String SUPPRESS_AUTO_APPLY_OFF = 'auto_apply_disabled';

    /** Spec signature (REQUIREMENTS F5); policies override the definition's own list when given. */
    public static Gavel_Outcome evaluate(Gavel_Definition def, Gavel_JudgmentResponse resp, List<Gavel_Definition.Policy> policies) {
        if (policies != null) {
            def.policies = policies;
        }
        return evaluate(def, resp);
    }

    public static Gavel_Outcome evaluate(Gavel_Definition def, Gavel_JudgmentResponse resp) {
        Gavel_Outcome result = new Gavel_Outcome();
        Set<String> participating = new Set<String>();
        for (Gavel_Question q : def.participatingQuestions()) {
            participating.add(q.key);
        }
        List<String> asymmetric = new List<String>();
        for (Gavel_Question q : def.questions) {
            Gavel_Definition.Policy policy = def.policy(q.key);
            Gavel_Outcome.QuestionResult qr = evaluateQuestion(q, resp, policy);
            qr.participating = participating.contains(q.key);
            result.questions.put(q.key, qr);
            result.perQuestion.put(q.key, qr.outcome + ':' + qr.reason);
            if (qr.participating) {
                if (result.outcome == null || Gavel_Outcome.severity(qr.outcome) > Gavel_Outcome.severity(result.outcome)) {
                    result.outcome = qr.outcome;
                    result.reason = qr.reason;
                    result.decidingQuestion = q.key;
                }
                if (policy != null && String.isNotBlank(policy.asymmetricReason)) {
                    asymmetric.add(q.key + ': ' + policy.asymmetricReason);
                }
            }
        }
        if (result.outcome == null) {
            result.outcome = Gavel_Outcome.ERROR;
            result.reason = 'no_questions';
        }
        if (!asymmetric.isEmpty()) {
            result.asymmetricReason = String.join(asymmetric, ' | ').abbreviate(255);
        }
        applyMode(def, result);
        return result;
    }

    /** Shadow and Draft never act; Live with Auto_Apply__c off routes AUTO to review (Live-Review). */
    public static void applyMode(Gavel_Definition def, Gavel_Outcome result) {
        if (def.mode == Gavel_Definition.MODE_SHADOW) {
            result.actionSuppressed = true;
            result.suppressReason = SUPPRESS_SHADOW;
        } else if (def.mode == Gavel_Definition.MODE_DRAFT || def.mode == Gavel_Definition.MODE_RETIRED) {
            result.actionSuppressed = true;
            result.suppressReason = SUPPRESS_DRAFT;
        } else if (def.isLive() && def.autoApply != true && result.isAuto()) {
            result.actionSuppressed = true;
            result.suppressReason = SUPPRESS_AUTO_APPLY_OFF;
        }
    }

    public static Gavel_Outcome.QuestionResult evaluateQuestion(Gavel_Question q, Gavel_JudgmentResponse resp, Gavel_Definition.Policy policy) {
        Gavel_Outcome.QuestionResult qr = new Gavel_Outcome.QuestionResult();
        qr.key = q.key;
        qr.questionType = q.questionType;
        if (resp == null || !resp.isOk()) {
            return mark(qr, Gavel_Outcome.ERROR, resp == null || resp.status == null ? 'no_response' : resp.status);
        }
        Gavel_Answer a = resp.answers == null ? null : resp.answers.get(q.key);
        if (a == null || !a.isValid()) {
            return mark(qr, Gavel_Outcome.ERROR, R_INVALID_RESPONSE);
        }
        if (policy == null || policy.autoAccept == null || policy.reviewAt == null) {
            return mark(qr, Gavel_Outcome.ERROR, R_POLICY_MISSING);
        }
        if (q.isChoice()) {
            return choice(qr, q, a, policy);
        }
        if (q.isScore()) {
            return score(qr, a, policy);
        }
        return noul(qr, a, policy);
    }

    private static Gavel_Outcome.QuestionResult choice(Gavel_Outcome.QuestionResult qr, Gavel_Question q, Gavel_Answer a, Gavel_Definition.Policy p) {
        qr.answerValue = a.choice;
        Decimal top = a.probabilities == null ? null : a.probabilities.get(a.choice);
        if (top == null) {
            return mark(qr, Gavel_Outcome.ERROR, R_INVALID_RESPONSE);
        }
        Decimal runnerUp = 0;
        Boolean tie = false;
        for (String k : a.probabilities.keySet()) {
            if (k.equals(a.choice)) {
                continue;
            }
            Decimal v = a.probabilities.get(k);
            if (v > runnerUp) {
                runnerUp = v;
            }
            if (v == top) {
                tie = true;
            }
        }
        qr.policyValue = top;
        qr.calibrationValue = top;
        qr.margin = top - runnerUp;
        if (a.confidence == null) {
            return mark(qr, Gavel_Outcome.REVIEW, R_UNKNOWN_CONFIDENCE);
        }
        Gavel_Option winner = q.findOption(a.choice);
        if (winner != null && winner.isEscape == true) {
            return mark(qr, Gavel_Outcome.REVIEW, R_ESCAPE);
        }
        Decimal minMargin = p.minMargin == null ? 0 : p.minMargin;
        if (top < p.reviewAt) {
            return mark(qr, Gavel_Outcome.ESCALATE, R_BELOW_REVIEW);
        }
        if (!tie && top >= p.autoAccept && qr.margin >= minMargin) {
            return mark(qr, Gavel_Outcome.AUTO, R_ACCEPTED);
        }
        if (tie || qr.margin < minMargin) {
            return mark(qr, Gavel_Outcome.REVIEW, R_MARGIN);
        }
        return mark(qr, Gavel_Outcome.REVIEW, R_BELOW_AUTO);
    }

    private static Gavel_Outcome.QuestionResult score(Gavel_Outcome.QuestionResult qr, Gavel_Answer a, Gavel_Definition.Policy p) {
        qr.answerValue = a.score == null ? null : a.score.stripTrailingZeros().toPlainString();
        qr.policyValue = a.confidence;
        qr.calibrationValue = a.confidence;
        if (a.confidence == null) {
            return mark(qr, Gavel_Outcome.REVIEW, R_UNKNOWN_CONFIDENCE);
        }
        if (a.confidence < p.reviewAt) {
            return mark(qr, Gavel_Outcome.ESCALATE, R_BELOW_REVIEW);
        }
        if (a.confidence >= p.autoAccept) {
            return mark(qr, Gavel_Outcome.AUTO, R_ACCEPTED);
        }
        return mark(qr, Gavel_Outcome.REVIEW, R_BELOW_AUTO);
    }

    private static Gavel_Outcome.QuestionResult noul(Gavel_Outcome.QuestionResult qr, Gavel_Answer a, Gavel_Definition.Policy p) {
        Decimal prob = a.probability;
        Boolean trueIsAction = p.noulDirection != 'false_is_action';
        Decimal actionSide = trueIsAction ? prob : 1 - prob;
        String actionAnswer = trueIsAction ? 'true' : 'false';
        String noActionAnswer = trueIsAction ? 'false' : 'true';
        qr.policyValue = actionSide;
        qr.calibrationValue = Math.max(prob, 1 - prob);
        qr.answerValue = prob >= 0.5 ? 'true' : 'false';
        if (actionSide >= p.autoAccept) {
            qr.answerValue = actionAnswer;
            return mark(qr, Gavel_Outcome.AUTO, R_ACCEPTED);
        }
        if (actionSide <= Math.min(p.reviewAt, 1 - p.autoAccept)) {
            qr.answerValue = noActionAnswer;
            return mark(qr, Gavel_Outcome.AUTO, R_ACCEPTED_NO_ACTION);
        }
        if (actionSide >= p.reviewAt) {
            return mark(qr, Gavel_Outcome.REVIEW, R_BELOW_AUTO);
        }
        return mark(qr, Gavel_Outcome.ESCALATE, R_BELOW_REVIEW);
    }

    private static Gavel_Outcome.QuestionResult mark(Gavel_Outcome.QuestionResult qr, String outcome, String reason) {
        qr.outcome = outcome;
        qr.reason = reason;
        return qr;
    }
}
