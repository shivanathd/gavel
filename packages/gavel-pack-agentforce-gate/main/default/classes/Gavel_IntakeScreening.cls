/**
 * Intake screening for Email-to-Case and Web-to-Lead (AGT-001.5). Text sent: Case.Subject + Case.Description,
 * or Lead.Company + Lead.Description (see "Data leaving your org"). On a Live Input Screen definition:
 * pass -> Passed; block -> Blocked and routed to the human queue; review / skip -> Review / Skipped and routed
 * to the human queue. In Shadow the screen is only ledgered.
 */
public with sharing class Gavel_IntakeScreening {
    public static final String HUMAN_QUEUE = 'Gavel_Intake_Review';
    private static final Map<String, String> STATUS = new Map<String, String>{
        'pass' => 'Passed', 'review' => 'Review', 'block' => 'Blocked', 'skip' => 'Skipped'
    };

    public class Request {
        @InvocableVariable(label='Record Id' description='Case or Lead to screen' required=true)
        public Id recordId;
    }

    public class Result {
        @InvocableVariable(label='Recommendation')
        public String recommendation;
        @InvocableVariable(label='Screen Status')
        public String status;
        @InvocableVariable(label='Routed To Human Queue')
        public Boolean routed = false;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
    }

    @InvocableMethod(label='Gavel: Screen Intake' description='Screens a new Case or Lead before it is routed to an agent queue.' category='Gavel' callout=true)
    public static List<Result> screenRecords(List<Request> requests) {
        List<Id> ids = new List<Id>();
        for (Request r : requests == null ? new List<Request>() : requests) {
            ids.add(r.recordId);
        }
        return screen(ids);
    }

    public static List<Result> screen(List<Id> recordIds) {
        List<Result> out = new List<Result>();
        try {
            Map<Id, String> textById = texts(recordIds);
            List<Gavel_AgentActions.ScreenRequest> reqs = new List<Gavel_AgentActions.ScreenRequest>();
            for (Id rid : recordIds) {
                String task = rid != null && rid.getSObjectType() == Lead.SObjectType ? 'Qualify an inbound sales inquiry' : 'Resolve a customer support request';
                reqs.add(new Gavel_AgentActions.ScreenRequest(textById.get(rid), task, rid));
            }
            List<Gavel_AgentActions.ScreenResult> screened = Gavel_AgentActions.screenInput(reqs);
            Boolean live = !screened.isEmpty() && screened[0].mode == Gavel_Definition.MODE_LIVE;
            Id queueId = live ? queueId() : null;
            List<SObject> updates = new List<SObject>();
            for (Integer i = 0; i < recordIds.size(); i++) {
                Result res = new Result();
                res.recommendation = screened[i].recommendation;
                res.status = STATUS.get(res.recommendation);
                res.ledgerId = screened[i].ledgerId;
                if (live && recordIds[i] != null) {
                    SObject rec = recordIds[i].getSObjectType().newSObject(recordIds[i]);
                    rec.put('Gavel_Screen_Status__c', res.status);
                    if (res.recommendation != Gavel_AgentActions.PASS && queueId != null) {
                        rec.put('OwnerId', queueId);
                        res.routed = true;
                    }
                    updates.add(rec);
                }
                out.add(res);
            }
            if (!updates.isEmpty()) {
                Gavel_ActionExecutor.applying = true;
                try {
                    Database.update(updates, false);
                } finally {
                    Gavel_ActionExecutor.applying = false;
                }
            }
        } catch (Exception e) {
            out.clear();
            for (Integer i = 0; i < recordIds.size(); i++) {
                Result res = new Result();
                res.recommendation = Gavel_AgentActions.REVIEW;
                res.status = 'Review';
                out.add(res);
            }
        }
        return out;
    }

    private static Id queueId() {
        List<Group> q = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :HUMAN_QUEUE LIMIT 1];
        return q.isEmpty() ? null : q[0].Id;
    }

    /** Only these fields become screening text. Read in user mode. */
    private static Map<Id, String> texts(List<Id> ids) {
        Map<Id, String> result = new Map<Id, String>();
        Set<Id> caseIds = new Set<Id>();
        Set<Id> leadIds = new Set<Id>();
        for (Id rid : ids) {
            if (rid == null) {
                continue;
            }
            if (rid.getSObjectType() == Case.SObjectType) {
                caseIds.add(rid);
            } else if (rid.getSObjectType() == Lead.SObjectType) {
                leadIds.add(rid);
            }
        }
        if (!caseIds.isEmpty()) {
            for (Case c : [SELECT Id, Subject, Description FROM Case WHERE Id IN :caseIds WITH USER_MODE]) {
                result.put(c.Id, joinText(c.Subject, c.Description));
            }
        }
        if (!leadIds.isEmpty()) {
            for (Lead l : [SELECT Id, Company, Description FROM Lead WHERE Id IN :leadIds WITH USER_MODE]) {
                result.put(l.Id, joinText(l.Company, l.Description));
            }
        }
        return result;
    }

    private static String joinText(String a, String b) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(a)) {
            parts.add(a);
        }
        if (String.isNotBlank(b)) {
            parts.add(b);
        }
        return parts.isEmpty() ? null : String.join(parts, '\n');
    }
}
