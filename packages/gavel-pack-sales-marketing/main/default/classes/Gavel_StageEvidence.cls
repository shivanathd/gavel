/**
 * Stage evidence check (SM-001.6). Runs Gavel_Stage_Evidence and, when the definition is Live, sets the helper
 * field Opportunity.Gavel_Stage_Evidence_Status__c that a customer validation rule can reference:
 *   AUTO with every criterion true -> Verified; AUTO with any criterion false -> Missing Evidence;
 *   REVIEW, ESCALATE, ERROR or SKIP -> Needs Review (blocks the stage change).
 * In Shadow the result is ledgered only.
 */
public with sharing class Gavel_StageEvidence {
    public static final String DEFINITION = 'Gavel_Stage_Evidence';

    public class Request {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id opportunityId;
    }

    public class Result {
        @InvocableVariable(label='Status' description='Verified, Missing Evidence or Needs Review')
        public String status;
        @InvocableVariable(label='Outcome')
        public String outcome;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
    }

    @InvocableMethod(label='Gavel: Check Stage Evidence' description='Checks recent activity for the stage exit criteria.' category='Gavel' callout=true)
    public static List<Result> invoke(List<Request> requests) {
        List<Id> ids = new List<Id>();
        for (Request r : requests == null ? new List<Request>() : requests) {
            ids.add(r.opportunityId);
        }
        return check(ids);
    }

    public static List<Result> check(List<Id> opportunityIds) {
        List<Gavel_Runtime.RunRequest> runs = new List<Gavel_Runtime.RunRequest>();
        for (Id oid : opportunityIds) {
            runs.add(new Gavel_Runtime.RunRequest(oid, DEFINITION));
        }
        Gavel_Definition def = Gavel_DefinitionRepo.get(DEFINITION);
        Boolean live = def != null && def.isLive();
        List<Result> out = new List<Result>();
        List<Opportunity> updates = new List<Opportunity>();
        List<Gavel_Runtime.RunResult> results = Gavel_Runtime.runAll(runs);
        for (Integer i = 0; i < results.size(); i++) {
            Gavel_Runtime.RunResult res = results[i];
            Result r = new Result();
            r.outcome = res.outcome;
            r.ledgerId = res.ledgerId;
            r.status = status(res);
            if (live && opportunityIds[i] != null) {
                updates.add(new Opportunity(Id = opportunityIds[i], Gavel_Stage_Evidence_Status__c = r.status));
            }
            out.add(r);
        }
        if (!updates.isEmpty()) {
            Gavel_ActionExecutor.applying = true;
            try {
                Database.update(updates, false, AccessLevel.SYSTEM_MODE); // Gavel-managed helper field
            } finally {
                Gavel_ActionExecutor.applying = false;
            }
        }
        return out;
    }

    public static String status(Gavel_Runtime.RunResult res) {
        if (res.outcome != Gavel_Outcome.AUTO) {
            return 'Needs Review';
        }
        for (String v : res.answerValues.values()) {
            if (v != 'true') {
                return 'Missing Evidence';
            }
        }
        return 'Verified';
    }
}
