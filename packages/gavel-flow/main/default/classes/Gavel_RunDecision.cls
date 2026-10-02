/**
 * Flow action "Gavel: Run Decision" (FLOW-001.1). For screen flows and autolaunched flows with no pending DML.
 * AUTO actions are not applied here: call "Gavel: Apply Outcome" with the returned ledger id.
 * Never throws into Flow (FLOW-001.7): errors come back as outcome ERROR with a reason.
 */
public with sharing class Gavel_RunDecision {
    public static final Integer MAX_SYNC = 50;

    public class RunInput {
        @InvocableVariable(label='Record Id' description='Record the decision is about' required=true)
        public Id recordId;
        @InvocableVariable(label='Definition API Name' description='Gavel_Decision__mdt DeveloperName' required=true)
        public String definitionApiName;
    }

    public class RunOutput {
        @InvocableVariable(label='Outcome' description='AUTO, REVIEW, ESCALATE, SKIP, ERROR or PENDING')
        public String outcome;
        @InvocableVariable(label='Reason')
        public String reason;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
        @InvocableVariable(label='Top Choice' description='Answer of the first choice question')
        public String topChoice;
        @InvocableVariable(label='Top Confidence')
        public Decimal topConfidence;
        @InvocableVariable(label='Answers JSON' description='Full typed answers and per-question outcomes')
        public String answersJson;
    }

    @InvocableMethod(label='Gavel: Run Decision' description='Runs a Gavel decision now and returns the policy outcome. Works with TypeSafe Jev.' category='Gavel' callout=true)
    public static List<RunOutput> run(List<RunInput> inputs) {
        List<RunOutput> outputs = new List<RunOutput>();
        if (inputs == null) {
            return outputs;
        }
        try {
            List<Gavel_Runtime.RunRequest> requests = new List<Gavel_Runtime.RunRequest>();
            for (Integer i = 0; i < inputs.size() && i < MAX_SYNC; i++) {
                RunInput input = inputs[i];
                Gavel_Runtime.RunRequest r = new Gavel_Runtime.RunRequest(input == null ? null : input.recordId, input == null ? null : input.definitionApiName);
                r.applyActions = false;
                requests.add(r);
            }
            for (Gavel_Runtime.RunResult res : Gavel_Runtime.runAll(requests)) {
                outputs.add(toOutput(res));
            }
            for (Integer i = MAX_SYNC; i < inputs.size(); i++) {
                outputs.add(error('sync_limit_exceeded_use_async'));
            }
        } catch (Exception e) {
            outputs.clear();
            for (Integer i = 0; i < inputs.size(); i++) {
                outputs.add(error('internal_error:' + e.getTypeName()));
            }
        }
        return outputs;
    }

    public static RunOutput toOutput(Gavel_Runtime.RunResult res) {
        RunOutput o = new RunOutput();
        o.outcome = res.outcome;
        o.reason = res.reason;
        o.ledgerId = res.ledgerId;
        o.topChoice = res.topChoice;
        o.topConfidence = res.topConfidence;
        o.answersJson = res.answersJson;
        return o;
    }

    public static RunOutput error(String reason) {
        RunOutput o = new RunOutput();
        o.outcome = Gavel_Outcome.ERROR;
        o.reason = reason;
        return o;
    }
}
