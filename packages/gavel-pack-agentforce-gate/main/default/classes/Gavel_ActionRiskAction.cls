/**
 * Agent action / Flow action "Gavel: Check Action Risk" (AGT-001.3). Never throws; unknown risk is manual_review.
 */
public with sharing class Gavel_ActionRiskAction {
    public class Request {
        @InvocableVariable(label='Action Description' description='What the agent wants to do' required=true)
        public String actionDescription;
        @InvocableVariable(label='Target Summary' description='What the action touches')
        public String targetSummary;
        @InvocableVariable(label='Related Record Id')
        public Id recordId;
    }

    public class Result {
        @InvocableVariable(label='Label' description='read_only, reversible, destructive or manual_review')
        public String label;
        @InvocableVariable(label='Outcome')
        public String outcome;
        @InvocableVariable(label='Safe To Run' description='True only for AUTO read_only or reversible')
        public Boolean safeToRun;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
    }

    @InvocableMethod(label='Gavel: Check Action Risk' description='Labels an agent action as read only, reversible or destructive before it runs.' category='Gavel' callout=true)
    public static List<Result> check(List<Request> requests) {
        List<Result> out = new List<Result>();
        if (requests == null) {
            return out;
        }
        try {
            List<Gavel_AgentActions.RiskRequest> reqs = new List<Gavel_AgentActions.RiskRequest>();
            for (Request r : requests) {
                reqs.add(new Gavel_AgentActions.RiskRequest(r == null ? null : r.actionDescription, r == null ? null : r.targetSummary, r == null ? null : r.recordId));
            }
            for (Gavel_AgentActions.RiskResult rr : Gavel_AgentActions.checkActionRisk(reqs)) {
                Result res = new Result();
                res.label = rr.label;
                res.outcome = rr.outcome;
                res.safeToRun = Gavel_AgentActions.safeToRun(rr);
                res.ledgerId = rr.ledgerId;
                out.add(res);
            }
        } catch (Exception e) {
            out.clear();
            for (Integer i = 0; i < requests.size(); i++) {
                Result res = new Result();
                res.label = 'manual_review';
                res.outcome = Gavel_Outcome.ERROR;
                res.safeToRun = false;
                out.add(res);
            }
        }
        return out;
    }
}
