/**
 * Agent action / Flow action "Gavel: Screen Input" (AGT-001.3). Never throws; fails closed to "review".
 */
public with sharing class Gavel_ScreenInputAction {
    public class Request {
        @InvocableVariable(label='Text' description='Inbound text to screen (email body, form text, chat message)' required=true)
        public String text;
        @InvocableVariable(label='Task Description' description='What the agent is supposed to do with this text')
        public String taskDescription;
        @InvocableVariable(label='Related Record Id' description='Optional record the text belongs to')
        public Id recordId;
    }

    public class Result {
        @InvocableVariable(label='Recommendation' description='pass, review, block or skip')
        public String recommendation;
        @InvocableVariable(label='Outcome')
        public String outcome;
        @InvocableVariable(label='Reason')
        public String reason;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
    }

    @InvocableMethod(label='Gavel: Screen Input' description='Screens text for instructions aimed at an AI agent before the agent reads it. Advisory unless wired as the only path.' category='Gavel' callout=true)
    public static List<Result> screen(List<Request> requests) {
        List<Result> out = new List<Result>();
        if (requests == null) {
            return out;
        }
        try {
            List<Gavel_AgentActions.ScreenRequest> reqs = new List<Gavel_AgentActions.ScreenRequest>();
            for (Request r : requests) {
                reqs.add(new Gavel_AgentActions.ScreenRequest(r == null ? null : r.text, r == null ? null : r.taskDescription, r == null ? null : r.recordId));
            }
            for (Gavel_AgentActions.ScreenResult s : Gavel_AgentActions.screenInput(reqs)) {
                Result res = new Result();
                res.recommendation = s.recommendation;
                res.outcome = s.outcome;
                res.reason = s.reason;
                res.ledgerId = s.ledgerId;
                out.add(res);
            }
        } catch (Exception e) {
            out.clear();
            for (Integer i = 0; i < requests.size(); i++) {
                Result res = new Result();
                res.recommendation = Gavel_AgentActions.REVIEW;
                res.outcome = Gavel_Outcome.ERROR;
                res.reason = 'internal_error:' + e.getTypeName();
                out.add(res);
            }
        }
        return out;
    }
}
