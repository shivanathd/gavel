/**
 * "Gavel: Guarded Action" (AGT-001.4): runs Action Risk before a wrapped subflow. On a Live definition the
 * subflow runs only for AUTO read_only or reversible; anything else (destructive, unsure, error, breaker open)
 * creates a Gavel_Review__c and the subflow does not run. In Shadow the gate only observes and ledgers.
 * The gate enforces only when the wrapped action is reachable solely through this wrapper (ADR-014).
 */
public with sharing class Gavel_GuardedAction {
    public class Request {
        @InvocableVariable(label='Action Description' required=true)
        public String actionDescription;
        @InvocableVariable(label='Target Summary')
        public String targetSummary;
        @InvocableVariable(label='Subflow API Name' description='Autolaunched flow to run when the action is safe' required=true)
        public String subflowApiName;
        @InvocableVariable(label='Record Id' description='Passed to the subflow as recordId')
        public Id recordId;
    }

    public class Result {
        @InvocableVariable(label='Executed')
        public Boolean executed = false;
        @InvocableVariable(label='Risk Label')
        public String label;
        @InvocableVariable(label='Outcome')
        public String outcome;
        @InvocableVariable(label='Review Id')
        public Id reviewId;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
        @InvocableVariable(label='Detail')
        public String detail;
    }

    /** Test seam: records subflow starts instead of launching flows that do not exist in the test org. */
    @TestVisible
    private static List<String> startedFlows;

    @InvocableMethod(label='Gavel: Guarded Action' description='Runs Action Risk, then the subflow only if the action is safe; otherwise creates a review.' category='Gavel' callout=true)
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        if (requests == null) {
            return out;
        }
        try {
            List<Gavel_AgentActions.RiskRequest> risks = new List<Gavel_AgentActions.RiskRequest>();
            for (Request r : requests) {
                risks.add(new Gavel_AgentActions.RiskRequest(r.actionDescription, r.targetSummary, r.recordId));
            }
            List<Gavel_AgentActions.RiskResult> results = Gavel_AgentActions.checkActionRisk(risks);
            List<Result> held = new List<Result>();
            for (Integer i = 0; i < requests.size(); i++) {
                Gavel_AgentActions.RiskResult rr = results[i];
                Result res = new Result();
                res.label = rr.label;
                res.outcome = rr.outcome;
                res.ledgerId = rr.ledgerId;
                Boolean live = rr.mode == Gavel_Definition.MODE_LIVE;
                if (!live || Gavel_AgentActions.safeToRun(rr)) {
                    res.detail = live ? 'safe_to_run' : 'shadow_observe_only';
                    res.executed = startSubflow(requests[i].subflowApiName, requests[i].recordId, res);
                } else {
                    res.detail = rr.label == 'destructive' ? 'destructive_action_held' : 'action_held_for_review';
                    held.add(res);
                }
                out.add(res);
            }
            if (!held.isEmpty()) {
                new ReviewWriter().write(held);
            }
        } catch (Exception e) {
            out.clear();
            for (Integer i = 0; i < requests.size(); i++) {
                Result res = new Result();
                res.outcome = Gavel_Outcome.ERROR;
                res.label = 'manual_review';
                res.detail = 'internal_error:' + e.getTypeName();
                out.add(res);
            }
        }
        return out;
    }

    private static Boolean startSubflow(String flowName, Id recordId, Result res) {
        if (String.isBlank(flowName)) {
            res.detail = 'subflow_missing';
            return false;
        }
        if (Test.isRunningTest() && startedFlows != null) {
            startedFlows.add(flowName);
            return true;
        }
        try {
            Flow.Interview.createInterview(flowName, new Map<String, Object>{ 'recordId' => recordId }).start();
            return true;
        } catch (Exception e) {
            res.detail = 'subflow_failed:' + e.getTypeName();
            return false;
        }
    }

    /** Review items are Gavel records: created in system mode so an agent user cannot skip them. */
    private without sharing class ReviewWriter {
        public void write(List<Result> held) {
            Set<Id> ledgerIds = new Set<Id>();
            for (Result r : held) {
                if (r.ledgerId != null) {
                    ledgerIds.add(r.ledgerId);
                }
            }
            Map<Id, Id> existing = new Map<Id, Id>();
            for (Gavel_Review__c rv : [SELECT Id, Decision_Log__c FROM Gavel_Review__c WHERE Decision_Log__c IN :ledgerIds WITH SYSTEM_MODE]) {
                existing.put(rv.Decision_Log__c, rv.Id);
            }
            List<Group> queue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Gavel_Review_Queue' WITH SYSTEM_MODE LIMIT 1];
            Map<Id, Gavel_Decision_Log__c> logs = new Map<Id, Gavel_Decision_Log__c>([
                SELECT Id, Definition__c, Record_Id__c, Outcome__c, Case__c, Lead__c, Contact__c, Opportunity__c
                FROM Gavel_Decision_Log__c WHERE Id IN :ledgerIds WITH SYSTEM_MODE
            ]);
            List<Gavel_Review__c> rows = new List<Gavel_Review__c>();
            List<Result> forRows = new List<Result>();
            for (Result r : held) {
                if (r.ledgerId != null && existing.containsKey(r.ledgerId)) {
                    r.reviewId = existing.get(r.ledgerId);
                    continue;
                }
                Gavel_Decision_Log__c log = logs.get(r.ledgerId);
                Gavel_Review__c rv = new Gavel_Review__c(
                    Decision_Log__c = r.ledgerId,
                    Definition__c = Gavel_AgentActions.ACTION_RISK,
                    Record_Id__c = log == null ? null : log.Record_Id__c,
                    Outcome__c = r.outcome,
                    Reason__c = r.detail,
                    Question_Key__c = 'risk',
                    Gavel_Value__c = r.label,
                    Status__c = 'Open',
                    Case__c = log == null ? null : log.Case__c,
                    Lead__c = log == null ? null : log.Lead__c,
                    Contact__c = log == null ? null : log.Contact__c,
                    Opportunity__c = log == null ? null : log.Opportunity__c
                );
                if (!queue.isEmpty()) {
                    rv.OwnerId = queue[0].Id;
                }
                rows.add(rv);
                forRows.add(r);
            }
            if (!rows.isEmpty()) {
                insert as system rows;
                for (Integer i = 0; i < rows.size(); i++) {
                    forRows[i].reviewId = rows[i].Id;
                }
            }
        }
    }
}
