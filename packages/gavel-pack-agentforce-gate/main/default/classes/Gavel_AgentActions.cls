/**
 * Agentforce Gate logic (F10). Screening fails closed: a provider error, an open breaker or an exhausted budget
 * gives "review", never "pass" (AGT-001.7). The gate is advisory unless the agent can only reach the wrapped
 * action through Gavel_GuardedAction (ADR-014).
 */
public with sharing class Gavel_AgentActions {
    public static final String INPUT_SCREEN = 'Gavel_Input_Screen';
    public static final String ACTION_RISK = 'Gavel_Action_Risk';
    public static final String PASS = 'pass';
    public static final String REVIEW = 'review';
    public static final String BLOCK = 'block';
    public static final String SKIP = 'skip';

    public class ScreenRequest {
        public String text;
        public String taskDescription;
        public Id recordId;

        public ScreenRequest(String text, String taskDescription, Id recordId) {
            this.text = text;
            this.taskDescription = taskDescription;
            this.recordId = recordId;
        }
    }

    public class ScreenResult {
        public String recommendation;
        public String outcome;
        public String reason;
        public Id ledgerId;
        public String mode;
    }

    public class RiskRequest {
        public String actionDescription;
        public String targetSummary;
        public Id recordId;

        public RiskRequest(String actionDescription, String targetSummary, Id recordId) {
            this.actionDescription = actionDescription;
            this.targetSummary = targetSummary;
            this.recordId = recordId;
        }
    }

    public class RiskResult {
        public String label;
        public String outcome;
        public String reason;
        public Id ledgerId;
        public String mode;
    }

    public static List<ScreenResult> screenInput(List<ScreenRequest> requests) {
        List<Gavel_Runtime.RunRequest> runs = new List<Gavel_Runtime.RunRequest>();
        for (ScreenRequest r : requests) {
            Gavel_Runtime.RunRequest rr = new Gavel_Runtime.RunRequest(r.recordId, INPUT_SCREEN);
            rr.inputs = new Map<String, Object>{ 'text' => r.text, 'taskDescription' => r.taskDescription };
            runs.add(rr);
        }
        List<ScreenResult> out = new List<ScreenResult>();
        Gavel_Definition def = Gavel_DefinitionRepo.get(INPUT_SCREEN);
        for (Gavel_Runtime.RunResult res : Gavel_Runtime.runAll(runs)) {
            ScreenResult s = new ScreenResult();
            s.outcome = res.outcome;
            s.reason = res.reason;
            s.ledgerId = res.ledgerId;
            s.mode = def == null ? null : def.mode;
            s.recommendation = recommendation(res);
            out.add(s);
        }
        return out;
    }

    /**
     * pass / review / block / skip (AGT-001.1). Fail closed: anything that is not a confident judgment is review,
     * except missing text, which is skip (no_substance) and is routed per config (default: a person).
     */
    public static String recommendation(Gavel_Runtime.RunResult res) {
        if (res == null || res.outcome == null || res.outcome == Gavel_Outcome.ERROR) {
            return REVIEW;
        }
        if (res.outcome == Gavel_Outcome.SKIP) {
            return res.reason == Gavel_StateBuilder.INSUFFICIENT_STATE ? SKIP : REVIEW;
        }
        String injection = res.perQuestion.get('agent_instructions');
        if (injection != null && injection.startsWith(Gavel_Outcome.AUTO) && res.answerValues.get('agent_instructions') == 'true') {
            return BLOCK;
        }
        for (String v : res.perQuestion.values()) {
            if (!v.startsWith(Gavel_Outcome.AUTO)) {
                return REVIEW;
            }
        }
        if (res.answerValues.get('has_substance') == 'false') {
            return SKIP;
        }
        if (res.answerValues.get('task_relevant') == 'false') {
            return REVIEW;
        }
        return PASS;
    }

    public static List<RiskResult> checkActionRisk(List<RiskRequest> requests) {
        List<Gavel_Runtime.RunRequest> runs = new List<Gavel_Runtime.RunRequest>();
        for (RiskRequest r : requests) {
            Gavel_Runtime.RunRequest rr = new Gavel_Runtime.RunRequest(r.recordId, ACTION_RISK);
            rr.inputs = new Map<String, Object>{ 'actionDescription' => r.actionDescription, 'targetSummary' => r.targetSummary };
            runs.add(rr);
        }
        List<RiskResult> out = new List<RiskResult>();
        Gavel_Definition def = Gavel_DefinitionRepo.get(ACTION_RISK);
        for (Gavel_Runtime.RunResult res : Gavel_Runtime.runAll(runs)) {
            RiskResult r = new RiskResult();
            r.outcome = res.outcome;
            r.reason = res.reason;
            r.ledgerId = res.ledgerId;
            r.mode = def == null ? null : def.mode;
            r.label = res.answerValues.containsKey('risk') && res.answerValues.get('risk') != null ? res.answerValues.get('risk') : 'manual_review';
            out.add(r);
        }
        return out;
    }

    /** Safe to run without a person: AUTO on read_only or reversible. Everything else is held. */
    public static Boolean safeToRun(RiskResult r) {
        return r.outcome == Gavel_Outcome.AUTO && (r.label == 'read_only' || r.label == 'reversible');
    }
}
