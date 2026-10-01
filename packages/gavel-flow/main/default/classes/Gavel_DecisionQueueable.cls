/**
 * Async runner (FLOW-001.2). Finalizes up to Batch_Size__c PENDING ledger entries per job, one callout per
 * record, retries allowed (async). A backlog is chained to the next job when the platform allows it;
 * otherwise it stays PENDING for Gavel_PendingSweeper.
 */
public with sharing class Gavel_DecisionQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> ledgerIds;
    private List<Id> backlog;

    public Gavel_DecisionQueueable(List<Id> ledgerIds, List<Id> backlog) {
        this.ledgerIds = ledgerIds;
        this.backlog = backlog == null ? new List<Id>() : backlog;
    }

    public void execute(QueueableContext ctx) {
        process(ledgerIds);
        if (!backlog.isEmpty() && canChain()) {
            Integer size = Gavel_Config.ops().batchSize;
            List<Id> next = new List<Id>();
            List<Id> rest = new List<Id>();
            for (Integer i = 0; i < backlog.size(); i++) {
                if (i < size) {
                    next.add(backlog[i]);
                } else {
                    rest.add(backlog[i]);
                }
            }
            System.enqueueJob(new Gavel_DecisionQueueable(next, rest));
        }
    }

    private static Boolean canChain() {
        return !Test.isRunningTest() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
    }

    /** Runs the still-PENDING entries among the given ids. Shared with Gavel_PendingSweeper. */
    public static List<Gavel_Runtime.RunResult> process(List<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Gavel_Runtime.RunResult>();
        }
        Map<Id, Gavel_Decision_Log__c> entries = Gavel_Ledger.load(new Set<Id>(ids));
        List<Gavel_Runtime.RunRequest> requests = new List<Gavel_Runtime.RunRequest>();
        for (Id i : ids) {
            Gavel_Decision_Log__c e = entries.get(i);
            if (e == null || e.Outcome__c != Gavel_Outcome.PENDING) {
                continue; // already finalized (sweeper race) or purged
            }
            Gavel_Runtime.RunRequest r = new Gavel_Runtime.RunRequest(toId(e.Record_Id__c), e.Definition__c);
            r.pendingEntry = e;
            r.isAsync = true;
            r.applyActions = true;
            requests.add(r);
        }
        return requests.isEmpty() ? new List<Gavel_Runtime.RunResult>() : Gavel_Runtime.runAll(requests);
    }

    private static Id toId(String value) {
        try {
            return String.isBlank(value) || value == 'none' ? null : Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }
}
